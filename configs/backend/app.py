import os
import pymysql
from flask import Flask, jsonify, request

app = Flask(__name__)

DB_HOST = os.getenv("DB_HOST", "127.0.0.1")
DB_USER = os.getenv("DB_USER")
DB_PASS = os.getenv("DB_PASS")
DB_NAME = os.getenv("DB_NAME")
APP_PORT = int(os.getenv("APP_PORT", 5000))

def get_db_connection():
    return pymysql.connect(
        host=DB_HOST,
        user=DB_USER,
        password=DB_PASS,
        database=DB_NAME,
        cursorclass=pymysql.cursors.DictCursor
    )

# Endpoint Đọc (GET)
@app.route("/", methods=["GET"])
@app.route("/api/items", methods=["GET"])
def get_items():
    conn = get_db_connection()
    with conn.cursor() as cursor:
        cursor.execute("SELECT id, name, created_at FROM items ORDER BY id DESC")
        items = cursor.fetchall()
    conn.close()
    return jsonify({"status": "success", "data": items}), 200

# Endpoint Ghi (POST)
@app.route("/api/items", methods=["POST"])
def create_item():
    data = request.get_json(silent=True) or {}
    name = data.get("name") or request.form.get("name")
    if not name:
        return jsonify({"status": "error", "message": "Missing 'name'"}), 400

    conn = get_db_connection()
    with conn.cursor() as cursor:
        cursor.execute("INSERT INTO items (name) VALUES (%s)", (name,))
        conn.commit()
        new_id = cursor.lastrowid
    conn.close()
    return jsonify({"status": "success", "id": new_id, "name": name}), 201

# Endpoint Healthcheck
@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "healthy"}), 200

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=APP_PORT)
