const https = require("https");
const fs = require("fs");
const express = require("express");
const bodyParser = require("body-parser");
const session = require("express-session");
const mysql = require("mysql2/promise");

const app = express();
const PORT = process.env.PORT || 8080;

// Read the self-signed certificate and key files
const httpsOptions = {
  key: fs.readFileSync("server.key"),   // Ensure server.key is in the project folder
  cert: fs.readFileSync("server.cert")    // Ensure server.cert is in the project folder
};

// Middleware
app.use(bodyParser.urlencoded({ extended: false }));
app.use(session({
  secret: "mySuperSecretKey", // In production, store this securely
  resave: false,
  saveUninitialized: true
}));

// Create a MySQL connection pool
const pool = mysql.createPool({
  host: process.env.DB_HOST || "mysqlserverctap.mysql.database.azure.com",
  user: process.env.DB_USER || "mysqladmin",
  password: process.env.DB_PASSWORD || "P@ssw0rd1234!",
  database: process.env.DB_NAME || "mydb",
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
  ssl: {
      rejectUnauthorized: false
    }
});

// Serve the login page or registration page
app.get("/", async (req, res) => {
  res.redirect("https://ctap-ui-webapp-renewed-boar.azurewebsites.net/");
});

// Updated registration endpoint to return a status code
app.post("/register", async (req, res) => {
  const { email, password } = req.body;
  try {
    const [rows] = await pool.query("SELECT * FROM users WHERE email = ?", [email]);
    if (rows.length > 0) {
      return res.status(400).send("User already exists.");
    }
    await pool.query("INSERT INTO users (email, password) VALUES (?, ?)", [email, password]);
    res.sendStatus(200);
  } catch (err) {
    console.error("Registration error:", err);
    // Temporarily return error details for debugging:
    res.status(500).send(`Registration failed: ${err.message}`);
  }
});

// Login endpoint: checks credentials against the MySQL database
app.post("/login", async (req, res) => {
  const { email, password } = req.body;
  try {
    const [rows] = await pool.query("SELECT * FROM users WHERE email = ? AND password = ?", [email, password]);
    if (rows.length > 0) {
      req.session.loggedIn = true;
      req.session.email = email;
      res.redirect("/");
    } else {
      res.send("Invalid credentials. <a href='/'>Try again</a>");
    }
  } catch (err) {
    console.error("Login error:", err);
    res.send("Error during login. <a href='/'>Try again</a>");
  }
});

// Logout endpoint
app.get("/logout", (req, res) => {
  req.session.destroy();
  res.redirect("/");
});

// Start the HTTPS server so the app is available at https://<public-ip>:8080/
https.createServer(httpsOptions, app).listen(PORT, () => {
  console.log(`HTTPS server running on port ${PORT}`);
});
