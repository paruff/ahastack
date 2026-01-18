# tests/unit/test_mqtt_connection.py
"""Unit tests for MQTT connection handling"""

from unittest.mock import Mock, patch

import paho.mqtt.client as mqtt
import pytest


class MQTTConnection:
    def __init__(self, host, port=1883):
        self.host = host
        self.port = port
        self.client = None
        self.connected = False

    def connect(self):
        self.client = mqtt.Client()
        self.client.connect(self.host, self.port)
        self.connected = True
        return True


@pytest.fixture
def mqtt_connection():
    return MQTTConnection("mosquitto")


def test_mqtt_initialization(mqtt_connection):
    """Test MQTT connection object initialization"""
    assert mqtt_connection.host == "mosquitto"
    assert mqtt_connection.port == 1883
    assert mqtt_connection.connected is False


@patch("paho.mqtt.client.Client")
def test_mqtt_connect(mock_client, mqtt_connection):
    """Test MQTT connection establishment"""
    mqtt_connection.connect()
    assert mqtt_connection.connected is True
    mock_client.assert_called_once()
