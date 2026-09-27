import os
from datetime import datetime
from flask import Flask, render_template, request, redirect, url_for
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import func
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)

BASE_DIR = os.path.abspath(os.path.dirname(__file__))
DATABASE_URL = os.getenv("DATABASE_URL") or f"sqlite:///{os.path.join(BASE_DIR, 'shop.db')}"

app.config["SQLALCHEMY_DATABASE_URI"] = DATABASE_URL
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False
app.config["SECRET_KEY"] = os.getenv("SECRET_KEY")

# Simple fallback for local dev when container uses SQLite DB
if DATABASE_URL.startswith("postgres") and os.getenv("USE_SQLITE_FOR_LOCAL") == "1":
    app.config["SQLALCHEMY_DATABASE_URI"] = f"sqlite:///{os.path.join(BASE_DIR, 'shop.db')}"

db = SQLAlchemy(app)


class Product(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(120), nullable=False)
    category = db.Column(db.String(80), nullable=False)
    description = db.Column(db.Text, nullable=False)
    price = db.Column(db.Float, nullable=False)
    stock = db.Column(db.Integer, nullable=False, default=0)

    def __repr__(self):
        return f"<Product {self.name}>"


class Order(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    customer_name = db.Column(db.String(120), nullable=False)
    customer_email = db.Column(db.String(120), nullable=False)
    address = db.Column(db.Text, nullable=False)
    total_amount = db.Column(db.Float, nullable=False)
    status = db.Column(db.String(50), default="Placed")
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    items = db.relationship("OrderItem", backref="order", cascade="all, delete-orphan")


class OrderItem(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    order_id = db.Column(db.Integer, db.ForeignKey("order.id"), nullable=False)
    product_id = db.Column(db.Integer, db.ForeignKey("product.id"), nullable=False)
    product = db.relationship("Product")
    quantity = db.Column(db.Integer, nullable=False)
    unit_price = db.Column(db.Float, nullable=False)


with app.app_context():
    db.create_all()
    if Product.query.count() == 0:
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
        db.session.flush()

        for item in selected:
            db.session.add(OrderItem(
                order_id=order.id,
                product_id=item["product"].id,
                quantity=item["quantity"],
                unit_price=item["product"].price
            ))
            item["product"].stock -= item["quantity"]

        db.session.commit()
        return redirect(url_for("confirmation", order_id=order.id))

    products = Product.query.order_by(Product.category, Product.name).all()
    return render_template("order.html", products=products)


@app.route("/confirmation/<int:order_id>")
def confirmation(order_id):
    order = Order.query.get_or_404(order_id)
    return render_template("confirmation.html", order=order, items=order.items)


@app.route("/health")
def health():
    try:
        db.session.execute(db.text("SELECT 1"))
        return {"status": "ok", "database": "connected"}, 200
    except Exception:
        return {"status": "error", "database": "unavailable"}, 503


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", 5000)), debug=True)
