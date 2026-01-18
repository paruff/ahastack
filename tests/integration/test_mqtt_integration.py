# tests/integration/test_mqtt_integration.py
"""Integration tests for MQTT broker"""

import pytest
import paho.mqtt.client as mqtt
import time
import os


@pytest.fixture(scope="module")
def mqtt_client():
    """Create MQTT client for integration tests"""
    client = mqtt.Client()
    host = os.getenv("MQTT_HOST", "mosquitto")

    max_retries = 5
    for attempt in range(max_retries):
        try:
            client.connect(host, 1883, 60)
            client.loop_start()
            yield client
            client.loop_stop()
            client.disconnect()
            return
        except Exception:
            if attempt < max_retries - 1:
                time.sleep(2)
            else:
                raise


def test_mqtt_publish_subscribe(mqtt_client):
    """Test MQTT publish and subscribe functionality"""
    received_messages = []

    def on_message(client, userdata, msg):
        received_messages.append(msg.payload.decode())

    mqtt_client.on_message = on_message
    mqtt_client.subscribe("test/integration")

    # Give subscription time to register
    time.sleep(1)

    # Publish test message
    mqtt_client.publish("test/integration", "integration test message")

    # Wait for message
    time.sleep(2)

    assert len(received_messages) > 0
    assert "integration test message" in received_messages
