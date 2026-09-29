# Pilgrim Pantry: a small Flask storefront (menu browsing + order placement) used as the assignment demo app.
import json
import logging
import os
from datetime import datetime

import boto3
from flask import Flask, render_template, request, redirect, url_for
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import URL
from sqlalchemy.exc import SQLAlchemyError
from dotenv import load_dotenv
from botocore.exceptions import BotoCoreError, ClientError

load_dotenv()  # loads a local .env file for development; ignored in production where real env vars are set
logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))

app = Flask(__name__)

BASE_DIR = os.path.abspath(os.path.dirname(__file__))


def get_database_url():
    # In production DB_APP_SECRET_ARN is set, so credentials are fetched live from Secrets Manager instead of env vars.
    secret_arn = os.getenv("DB_APP_SECRET_ARN")
    if secret_arn:
        try:
            response = boto3.client(
                "secretsmanager", region_name=os.getenv("AWS_REGION")
            ).get_secret_value(SecretId=secret_arn)
            credentials = json.loads(response["SecretString"])
            return URL.create(
                "postgresql+psycopg2",
                username=credentials["username"],
                password=credentials["password"],
                host=credentials["host"],
                port=int(credentials["port"]),
                database=credentials["dbname"],
                query={
                    # Enforce TLS and verify the RDS server certificate against the downloaded AWS CA bundle.
                    "sslmode": "verify-full",
                    "sslrootcert": "/etc/ssl/certs/rds-global-bundle.pem",
                },
            )
        except (BotoCoreError, ClientError, KeyError, ValueError) as error:
            raise RuntimeError("Unable to load application database credentials") from error

    # Local/dev fallback: use DATABASE_URL if provided, otherwise a local SQLite file.
    return os.getenv("DATABASE_URL") or f"sqlite:///{os.path.join(BASE_DIR, 'shop.db')}"


DATABASE_URL = get_database_url()

app.config["SQLALCHEMY_DATABASE_URI"] = DATABASE_URL
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
app.config["SECRET_KEY"] = os.getenv("SECRET_KEY")

# Simple fallback for local dev when container uses SQLite DB
if (
    isinstance(DATABASE_URL, str)
    and DATABASE_URL.startswith("postgres")
    and os.getenv("USE_SQLITE_FOR_LOCAL") == "1"
):
    app.config["SQLALCHEMY_DATABASE_URI"] = f"sqlite:///{os.path.join(BASE_DIR, 'shop.db')}"

db = SQLAlchemy(app)


class Product(db.Model):
    # A menu item shown on the storefront, with live stock decremented on each order.
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(120), nullable=False)
    category = db.Column(db.String(80), nullable=False)
    description = db.Column(db.Text, nullable=False)
    price = db.Column(db.Float, nullable=False)
    stock = db.Column(db.Integer, nullable=False, default=0)

    def __repr__(self):
        return f"<Product {self.name}>"


class Order(db.Model):
    # A customer order; total_amount is computed server-side from the selected items at checkout time.
    id = db.Column(db.Integer, primary_key=True)
    customer_name = db.Column(db.String(120), nullable=False)
    customer_email = db.Column(db.String(120), nullable=False)
    address = db.Column(db.Text, nullable=False)
    total_amount = db.Column(db.Float, nullable=False)
    status = db.Column(db.String(50), default="Placed")
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    items = db.relationship("OrderItem", backref="order", cascade="all, delete-orphan")


class OrderItem(db.Model):
    # A single product line within an order, capturing the price at time of purchase.
    id = db.Column(db.Integer, primary_key=True)
    order_id = db.Column(db.Integer, db.ForeignKey("order.id"), nullable=False)
    product_id = db.Column(db.Integer, db.ForeignKey("product.id"), nullable=False)
    product = db.relationship("Product")
    quantity = db.Column(db.Integer, nullable=False)
    unit_price = db.Column(db.Float, nullable=False)


with app.app_context():
    db.create_all()  # creates tables on first run; no migrations yet, so schema changes require manual handling
    if Product.query.count() == 0:
        # Seed a fixed demo menu the first time the app starts against an empty database.
        seed_products = [
            Product(name="Pilgrim Saffron Rice Bowl", category="Main Course", description="Fragrant saffron rice with seasoned vegetables and herbs.", price=12.5, stock=20),
            Product(name="Fresh Herb Wrap", category="Fast Bite", description="Crisp vegetables, mint yogurt, and grilled chicken in a wrap.", price=9.0, stock=25),
            Product(name="Classic Pilgrim Pizza", category="Pizza", description="Wood-fired pizza with tomato, cheese, and olives.", price=14.75, stock=18),
            Product(name="Mango Lime Cooler", category="Drink", description="Refreshing citrus cooler with tropical mango and lime.", price=4.5, stock=40),
            Product(name="Crispy Paneer Platter", category="Starter", description="Golden fried paneer bites served with chilli dip.", price=8.25, stock=30),
        ]
        db.session.add_all(seed_products)
        db.session.commit()


@app.route("/")
def home():
    # Storefront landing page: lists all menu items grouped by category.
    products = Product.query.order_by(Product.category, Product.name).all()
    return render_template("index.html", products=products)


@app.route("/order", methods=["GET", "POST"])
def order_products():
    if request.method == "POST":
        customer_name = request.form.get("customer_name", "").strip()
        email = request.form.get("email", "").strip()
        address = request.form.get("address", "").strip()

        if not customer_name or not email or not address:
            return "Please complete your customer details before placing the order.", 400

        # Parse form fields named qty_<product_id> into a list of {product, quantity} selections.
        selected = []
        for key, value in request.form.items():
            if key.startswith("qty_"):
                product_id = int(key.replace("qty_", ""))
                qty = int(value or 0)
                if qty > 0:
                    product = Product.query.get(product_id)
                    if product and qty <= product.stock:
                        selected.append({"product": product, "quantity": qty})
                    else:
                        return f"Selected quantity for {product.name if product else 'an item'} exceeds available stock.", 400

        if not selected:
            return "Please select at least one item before placing the order.", 400

        total_amount = sum(item["product"].price * item["quantity"] for item in selected)

        order = Order(
            customer_name=customer_name,
            customer_email=email,
            address=address,
            total_amount=round(total_amount, 2),
            status="Placed"
        )
        db.session.add(order)
        db.session.flush()  # assigns order.id before creating dependent OrderItem rows

        for item in selected:
            db.session.add(OrderItem(
                order_id=order.id,
                product_id=item["product"].id,
                quantity=item["quantity"],
                unit_price=item["product"].price
            ))
            item["product"].stock -= item["quantity"]  # decrement stock atomically within the same transaction

        db.session.commit()
        return redirect(url_for("confirmation", order_id=order.id))

    products = Product.query.order_by(Product.category, Product.name).all()
    return render_template("order.html", products=products)


@app.route("/confirmation/<int:order_id>")
def confirmation(order_id):
    # Order receipt page shown right after checkout.
    order = Order.query.get_or_404(order_id)
    return render_template("confirmation.html", order=order, items=order.items)


@app.route("/health")
def health():
    # Used by the deploy script and load balancers/monitors to confirm the app can reach the database.
    try:
        db.session.execute(db.text("SELECT 1"))
        return {"status": "ok", "database": "connected"}, 200
    except SQLAlchemyError:
        app.logger.exception("Database health check failed")
        return {"status": "error", "database": "unavailable"}, 503


if __name__ == "__main__":
    # Only used for local development; production runs via Gunicorn (see deploy/pilgrim.service).
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", 5000)), debug=False)
