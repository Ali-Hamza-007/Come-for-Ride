

# 🚗 Come for Ride – Real-Time Ride Booking System

Come for Ride is a **full-stack real-time ride-hailing application** inspired by modern ride-booking platforms.
The system allows **passengers to request rides**, **drivers to bid for those rides**, and enables **real-time communication** between both using WebSockets.

This project demonstrates how **mobile applications, backend APIs, real-time systems, and databases** can work together to create a complete ride-booking platform.

---

# 📱 Application Overview

The application consists of:

* **Flutter Mobile App** – Used by passengers and drivers
* **Node.js + Express Backend** – Handles APIs and business logic
* **PostgreSQL Database** – Stores users, rides, and history
* **Socket.IO Server** – Enables real-time updates and communication

The system focuses on **efficient ride matching**, **live driver tracking**, and **dynamic fare negotiation**.

---

# 💡 Tech Stack

### Frontend (Mobile App)

* Flutter
* Dart
* Flutter Map
* Geolocator

### Backend

* Node.js
* Express.js
* Socket.IO

### Database

* PostgreSQL

### Authentication

* JSON Web Tokens (JWT)
* Bcrypt Password Hashing

### Real-Time Communication

* Socket.IO (WebSockets)

---

# ✨ Key Features

## 👤 Authentication System

* User registration
* Secure login
* JWT-based authentication
* Password hashing with Bcrypt

## 🚕 Ride Request System

Passengers can:

* Request a ride
* Enter pickup location
* Enter destination

Drivers can:

* Receive ride requests
* Send ride offers

---

## 💰 Dynamic Fare Bidding

Drivers can submit ride offers with different fares.

Passengers can:

* View all offers
* Compare driver bids
* Select the best offer

---

## 📍 Real-Time Driver Location

Drivers continuously send their **live GPS location**.

Passengers can:

* Track the driver on the map
* See real-time movement toward pickup location

---

## 💬 Real-Time Chat

Driver and passenger can communicate through:

* In-app chat
* Instant message updates via Socket.IO

---

## 🔔 Live Ride Status Updates

Ride events update instantly:

* Driver accepted ride
* Driver arrived
* Ride started
* Ride completed
* Ride cancelled

---

## 🧾 Ride History

All rides are stored in **PostgreSQL** including:

* Ride details
* Passenger information
* Driver information
* Fare amount
* Ride status

Users can view their **past ride history** anytime.

---

# ⚡ Real-Time Event System

The application uses **Socket.IO** for real-time features such as:

* Driver location updates
* Ride requests
* Ride bidding
* Chat messages
* Ride status changes

This ensures **low-latency communication** between drivers and passengers.

---

# 🏗️ System Architecture

```
Flutter Mobile App
        │
        │ REST API
        ▼
Node.js + Express Server
        │
        │ Socket.IO
        ▼
Real-Time Communication Layer
        │
        ▼
PostgreSQL Database
```

---

# 🖥️ Frontend Setup

- Change the IP Address in the variable found at top of .dart page ( got by typing " ipconfig " on cmd & copy IP address from That )
- flutter pub get
 
# 🖥️ Backend Setup

### Install dependencies

```
npm install
```


```
PORT=3000
JWT_SECRET=your_secret_key

DB_HOST=localhost
DB_USER=postgres
DB_PASSWORD=yourpassword
DB_NAME=come_for_ride
DB_PORT=5432
```

### Run Server

```
node server.js
```

or

```
npm start
```

---

