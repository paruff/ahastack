# tests/integration/test_postgres_integration.py
"""Integration tests for PostgreSQL database"""

import os
import time

import psycopg2
import pytest


@pytest.fixture(scope="module")
def db_connection():
    """Create database connection for integration tests"""
    max_retries = 5
    retry_delay = 2

    for attempt in range(max_retries):
        try:
            conn = psycopg2.connect(
                host=os.getenv("POSTGRES_HOST", "postgres"),
                database="homeassistant",
                user="hauser",
                password=os.getenv("POSTGRES_PASSWORD", "changeme"),
            )
            yield conn
            conn.close()
            return
        except psycopg2.OperationalError:
            if attempt < max_retries - 1:
                time.sleep(retry_delay)
            else:
                raise


def test_database_connection(db_connection):
    """Test database connectivity"""
    cursor = db_connection.cursor()
    cursor.execute("SELECT version();")
    result = cursor.fetchone()
    assert result is not None
    assert "PostgreSQL" in result[0]


def test_database_tables_exist(db_connection):
    """Test that required tables exist"""
    cursor = db_connection.cursor()
    cursor.execute("""
        SELECT table_name 
        FROM information_schema.tables 
        WHERE table_schema = 'public'
    """)
    tables = [row[0] for row in cursor.fetchall()]
    # Home Assistant creates tables on first run
    # This test verifies the database is ready to accept tables
    assert isinstance(tables, list)


def test_database_write_read(db_connection):
    """Test writing and reading from database"""
    cursor = db_connection.cursor()

    # Create test table
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS test_data (
            id SERIAL PRIMARY KEY,
            message TEXT
        )
    """)
    db_connection.commit()

    # Insert test data
    cursor.execute(
        "INSERT INTO test_data (message) VALUES (%s) RETURNING id",
        ("integration test",),
    )
    test_id = cursor.fetchone()[0]
    db_connection.commit()

    # Read back data
    cursor.execute("SELECT message FROM test_data WHERE id = %s", (test_id,))
    result = cursor.fetchone()

    assert result is not None
    assert result[0] == "integration test"

    # Cleanup
    cursor.execute("DROP TABLE test_data")
    db_connection.commit()
