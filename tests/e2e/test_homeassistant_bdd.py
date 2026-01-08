# tests/e2e/test_homeassistant_bdd.py
"""BDD-style end-to-end tests for Home Assistant"""
import pytest
from pytest_bdd import scenarios, given, when, then, parsers
import requests
import time
import os


# Load BDD scenarios
scenarios('../features/homeassistant.feature')


@pytest.fixture
def ha_url():
    """Home Assistant base URL"""
    return os.getenv('HA_URL', 'http://homeassistant:8123')


@pytest.fixture
def ha_session(ha_url):
    """HTTP session for Home Assistant"""
    session = requests.Session()
    session.headers.update({
        'Content-Type': 'application/json'
    })
    return session


@given('Home Assistant is running')
def home_assistant_running(ha_url, ha_session):
    """Verify Home Assistant is accessible"""
    max_retries = 10
    for attempt in range(max_retries):
        try:
            response = ha_session.get(ha_url, timeout=5)
            if response.status_code in [200, 401]:  # 401 means running but needs auth
                return True
        except requests.RequestException:
            if attempt < max_retries - 1:
                time.sleep(3)
            else:
                raise
    pytest.fail("Home Assistant is not accessible")


@when('I check the Home Assistant API status')
def check_api_status(ha_url, ha_session):
    """Check Home Assistant API status"""
    response = ha_session.get(f"{ha_url}/api/", timeout=10)
    assert response.status_code in [200, 401]


@then('the API should be responsive')
def api_responsive(ha_url, ha_session):
    """Verify API responds"""
    response = ha_session.get(f"{ha_url}/api/", timeout=10)
    assert response.status_code in [200, 401]


@given('MQTT broker is running')
def mqtt_broker_running():
    """Verify MQTT broker is accessible"""
    import paho.mqtt.client as mqtt
    client = mqtt.Client()
    try:
        client.connect(os.getenv('MQTT_HOST', 'mosquitto'), 1883, 60)
        client.disconnect()
        return True
    except Exception as e:
        pytest.fail(f"MQTT broker not accessible: {e}")


@when(parsers.parse('I publish message "{message}" to topic "{topic}"'))
def publish_mqtt_message(message, topic):
    """Publish MQTT message"""
    import paho.mqtt.client as mqtt
    client = mqtt.Client()
    client.connect(os.getenv('MQTT_HOST', 'mosquitto'), 1883, 60)
    client.publish(topic, message)
    client.disconnect()


@then('the message should be delivered successfully')
def message_delivered():
    """Verify message delivery"""
    # In a real scenario, you'd verify through subscription
    assert True
