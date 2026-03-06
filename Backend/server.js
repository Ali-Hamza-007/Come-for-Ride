const PORT = 3000;
const express = require('express');
const { Pool } = require('pg');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const cors = require('cors');
const http = require('http');
const { Server } = require('socket.io');
const app = express();
require('dotenv').config();

app.use(express.json());
app.use(cors());

const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST']
  }
});



// PostgreSQL Connection

const pool = new Pool({
  user: 'postgres',
  host: 'localhost',
  database: 'ride_db',
  password: 'our_db_password',
  port: 5432,
});


const JWT_SECRET = process.env._JWT_SECRET || 'your_secret_key';

// --- ACTIVE DRIVER STATE ---
let activeDrivers = {}; // Stores online drivers: { socketId: { userId, name, coords } }


// --- SOCKET.IO LOGIC ---
io.on('connection', (socket) => {
  console.log('User connected:', socket.id);
  socket.on('driver_update_fare', (data) => {
    // data: { passengerSocketId, newFare, driverName, carType, lat, lng }
    if (data.passengerSocketId) {
      io.to(data.passengerSocketId).emit('offer_received', {
        driverSocketId: socket.id,
        driverName: data.driverName,
        price: data.newFare,
        carType: data.carType,
        lat: data.lat,
        lng: data.lng,
        isCounterOffer: true ,
        pickup: data.pickup,       // Keep addresses in the loop
      destination: data.destination// Flag to indicate this is a price change
      });
    }
  });
  socket.on('disconnect', () => {
    delete activeDrivers[socket.id];
    console.log('User disconnected:', socket.id);
  });
  socket.on('decline_fare', (data) => {
    // data: { passengerSocketId }
    if (data.passengerSocketId) {
      io.to(data.passengerSocketId).emit('fare_declined', {
        message: "Driver declined the offer"
      });
    }
  });
  socket.on('driver_arrived', (data) => {
    // data: { passengerSocketId }
    io.to(data.passengerSocketId).emit('driver_arrived', {
      message: "Your driver has arrived at the pickup location!"
    });
  });
  socket.on('ride_finished', (data) => {
    // data: { passengerSocketId }
    if (activeDrivers[socket.id]) {
      activeDrivers[socket.id].isBusy = false;
    }
    if (data.passengerSocketId) {
      io.to(data.passengerSocketId).emit('ride_finished', {
        message: "Trip completed. Hope you enjoyed your ride!"
      });
    }
  });
  
  // Handle fare updates from passenger
  socket.on('update_fare', (data) => {
    // data: { driverSocketId, newFare, passengerName }
    console.log(`Fare updated to ${data.newFare} by ${data.passengerName}`);

    if (data.driverSocketId) {
      io.to(data.driverSocketId).emit('fare_updated', {
        newFare: data.newFare,
        passengerName: data.passengerName,
        passengerSocketId: socket.id,
        pickup: data.pickup, 
      destination: data.destination // Driver can still respond
      });
    }
  });
  // Handle Chat
  socket.on('send_chat_message', (data) => {
    if (data.receiverSocketId) {
      console.log(`Sending private message to: ${data.receiverSocketId}`);

      // io.to ensures ONLY the specific person with that ID gets the message
      io.to(data.receiverSocketId).emit('receive_chat_message', {
        message: data.message,
        senderName: data.senderName,
        senderSocketId: socket.id, // The recipient needs this to verify the sender
      });
    }


  });
  

  // Passenger cancels the ride
  socket.on('cancel_ride', (data) => {
    if (data.driverSocketId) {
      if(activeDrivers[data.driverSocketId]) activeDrivers[data.driverSocketId].isBusy = false;
      io.to(data.driverSocketId).emit('ride_cancelled', {
        message: "The passenger has cancelled the trip.",
      });
    }
  });

  // 1. Driver goes online or updates location
  socket.on('driver_location_update', (data) => {
    // data: { driverId, name, lat, lng }
    activeDrivers[socket.id] = {
      socketId: socket.id,
      userId: data.driverId,
      name: data.name,
      coords: { lat: data.lat, lng: data.lng },
      isBusy: activeDrivers[socket.id]?.isBusy || false
    };
    console.log(`Location update from Driver: ${data.name}`);
  });

  //  Passenger requests a ride
  socket.on('request_ride', (rideData) => {
    // rideData: { userId, pickup: { lat, lng }, pickupAddress, destination, initialFare }
    console.log(`New ride request from Passenger ${rideData.userId}`);

    // Filter nearby drivers (Roughly 5km radius using coordinate difference)
    const nearbyDrivers = Object.values(activeDrivers).filter(driver => {
      const latDiff = Math.abs(driver.coords.lat - rideData.pickup.lat);
      const lngDiff = Math.abs(driver.coords.lng - rideData.pickup.lng);
      return latDiff < 0.05 && lngDiff < 0.05 && !driver.isBusy;;
    });

    console.log(`Found ${nearbyDrivers.length} nearby drivers.`);

    // Broadcast the request ONLY to nearby drivers
    nearbyDrivers.forEach(driver => {
      io.to(driver.socketId).emit('ride_request_received', {
        ...rideData,
        passengerSocketId: socket.id ,
        pickup: rideData.pickupAddress, 
        destination: rideData.destination// Crucial for the driver to reply back
      });
    });
  });
  
  socket.on('passenger_confirmed_selection', (data) => {
    // data: { selectedDriverSocketId, passengerName, pickup, destination }
    console.log(`Passenger ${socket.id} confirmed driver ${data.selectedDriverSocketId}`);

    // Mark the selected driver as busy
    if (activeDrivers[data.selectedDriverSocketId]) {
      activeDrivers[data.selectedDriverSocketId].isBusy = true;

      // Important: Notify ONLY the selected driver
      // This is what triggers the Chat UI in Flutter
      io.to(data.selectedDriverSocketId).emit('you_are_selected', {
        passengerSocketId: socket.id,
        passengerName: data.passengerName || "Passenger",
        pickup: data.pickup,
        destination: data.destination
      });
    }

    // Notify ALL OTHER drivers to clear their request dialogs
    socket.broadcast.emit('ride_request_closed', {
      passengerSocketId: socket.id,
      selectedDriverSocketId: data.selectedDriverSocketId
    });
  });

  // Driver sends a bid/offer back to the passenger
  socket.on('send_offer', (offerData) => {
    // 1. Get the current driver's data including their coords
    const driver = activeDrivers[socket.id];

    console.log(`Driver ${offerData.driverName} sent offer: Rs. ${offerData.price}`);

    // Send the offer ONLY to the specific passenger
    io.to(offerData.passengerSocketId).emit('offer_received', {
      driverName: offerData.driverName,
      driverId: offerData.driverId,
      price: offerData.price,
      carType: offerData.carType,
      driverSocketId: socket.id,
      isCounterOffer: false,
      lat: driver && driver.coords ? driver.coords.lat : 0.0,
      lng: driver && driver.coords ? driver.coords.lng : 0.0
    });
  });

  socket.on('disconnect', () => {
    delete activeDrivers[socket.id];
    console.log('User disconnected:', socket.id);
  });
});

// --- HTTP ROUTES ---

// Registration
app.post('/api/register', async (req, res) => {
  const { name, email, password } = req.body;
  const hashedPassword = await bcrypt.hash(password, 10);
  const role = email.endsWith('@driver.ride.com') ? 'driver' : 'passenger';

  try {
    const result = await pool.query(
      'INSERT INTO users (name, email, password, role) VALUES ($1, $2, $3, $4) RETURNING id, name, email, role',
      [name, email, hashedPassword, role]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: "User already exists or DB error" });
  }
});

// Login
app.post('/api/login', async (req, res) => {
  const { email, password } = req.body;
  try {
    const user = await pool.query('SELECT * FROM users WHERE email = $1', [email]);
    if (user.rows.length === 0) return res.status(404).json({ error: "User not found" });

    const validPass = await bcrypt.compare(password, user.rows[0].password);
    if (!validPass) return res.status(401).json({ error: "Invalid password" });

    const token = jwt.sign({ id: user.rows[0].id }, JWT_SECRET, { expiresIn: '1h' });

    res.json({
      token,
      user: {
        id: user.rows[0].id,
        name: user.rows[0].name,
        email: user.rows[0].email,
        role: user.rows[0].role
      }
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// Save Ride History
app.post('/api/history', async (req, res) => {
  const { userId, pickup, destination } = req.body;
  try {
    const result = await pool.query(
      'INSERT INTO ride_history (user_id, pickup_address, destination_address) VALUES ($1, $2, $3) RETURNING id',
      [userId, pickup, destination]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: "Failed to save history" });
  }
});

// Get User History
app.get('/api/history/:userId', async (req, res) => {
  const { userId } = req.params;
  try {
    const result = await pool.query(
      'SELECT * FROM ride_history WHERE user_id = $1 ORDER BY created_at DESC',
      [userId]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: "Failed to fetch history" });
  }
});
//Delete a single history item
app.delete('/api/history/:id', async (req, res) => {
  const { id } = req.params;
  try {
    await pool.query('DELETE FROM ride_history WHERE id = $1', [id]);
    res.json({ message: "Item deleted successfully" });
  } catch (err) {
    res.status(500).json({ error: "Failed to delete item" });
  }
});

// Clear all history for a specific user
app.delete('/api/history/all/:userId', async (req, res) => {
  const { userId } = req.params;
  try {
    await pool.query('DELETE FROM ride_history WHERE user_id = $1', [userId]);
    res.json({ message: "All history cleared" });
  } catch (err) {
    res.status(500).json({ error: "Failed to clear history" });
  }
});

// Start Server

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port : ${PORT}`);
});