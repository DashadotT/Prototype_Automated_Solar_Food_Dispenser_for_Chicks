// Configuration
const API_BASE_URL = window.location.origin;
const UPDATE_INTERVAL = 1000; // 1 second

// DOM Elements
let distanceValue, foodStatus, servoStatus, foodProgress, timestamp;

// Initialize when page loads
document.addEventListener('DOMContentLoaded', () => {
    // Get DOM elements
    distanceValue = document.getElementById('distanceValue');
    foodStatus = document.getElementById('foodStatus');
    servoStatus = document.getElementById('servoStatus');
    foodProgress = document.getElementById('foodProgress');
    timestamp = document.getElementById('timestamp');

    // Attach event listeners
    const dispenseBtn = document.getElementById('dispenseBtn');
    if (dispenseBtn) {
        dispenseBtn.addEventListener('click', handleDispense);
    }

    // Start auto-refresh
    fetchSensorData();
    setInterval(fetchSensorData, UPDATE_INTERVAL);
});

// Fetch sensor data from ESP32
async function fetchSensorData() {
    try {
        const response = await fetch(`${API_BASE_URL}/api/sensor`);
        if (!response.ok) throw new Error('Network response was not ok');

        const data = await response.json();
        updateUI(data);
    } catch (error) {
        console.error('Error fetching sensor data:', error);
        if (distanceValue) distanceValue.textContent = 'ERR';
        if (foodStatus) {
            foodStatus.textContent = 'OFFLINE';
            foodStatus.className = 'status unknown';
        }
    }
}

// Update UI with sensor data
function updateUI(data) {
    // Update distance
    if (distanceValue) {
        distanceValue.textContent = data.distance;
    }

    // Update food status based on distance thresholds
    let statusText = 'UNKNOWN';
    let statusClass = 'unknown';
    let progressPercent = 0;

    if (data.distance <= 10) {
        statusText = 'FULL';
        statusClass = 'full';
        progressPercent = 100;
    } else if (data.distance <= 25) {
        statusText = 'MEDIUM';
        statusClass = 'medium';
        progressPercent = 60;
    } else if (data.distance <= 60) {
        statusText = 'LOW';
        statusClass = 'low';
        progressPercent = 30;
    } else {
        statusText = 'EMPTY';
        statusClass = 'low';
        progressPercent = 0;
    }

    if (foodStatus) {
        foodStatus.textContent = statusText;
        foodStatus.className = `status ${statusClass}`;
    }

    // Update progress bar
    if (foodProgress) {
        foodProgress.style.width = `${progressPercent}%`;
    }

    // Update timestamp
    if (timestamp) {
        const now = new Date();
        timestamp.textContent = now.toLocaleTimeString();
    }
}

// Handle dispense button click
async function handleDispense() {
    const btn = document.getElementById('dispenseBtn');
    if (!btn) return;

    // Disable button during operation
    btn.disabled = true;
    btn.textContent = '⏳ Dispensing...';

    // Update servo status to OPEN
    if (servoStatus) {
        servoStatus.textContent = 'OPEN';
        servoStatus.className = 'status open';
    }

    try {
        const response = await fetch(`${API_BASE_URL}/api/dispense`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            }
        });

        if (!response.ok) throw new Error('Dispense command failed');

        const result = await response.json();
        console.log('Dispense response:', result);

        // Wait for servo to complete (2 seconds open + minor delay)
        setTimeout(() => {
            if (servoStatus) {
                servoStatus.textContent = 'CLOSED';
                servoStatus.className = 'status closed';
            }
        }, 2500);

    } catch (error) {
        console.error('Error dispensing food:', error);
        alert('Failed to dispense food. Check ESP32 connection.');

        // Reset servo status on error
        if (servoStatus) {
            servoStatus.textContent = 'CLOSED';
            servoStatus.className = 'status closed';
        }
    } finally {
        // Re-enable button after operation
        setTimeout(() => {
            btn.disabled = false;
            btn.textContent = '🍲 Dispense Food';
        }, 3000);
    }
}