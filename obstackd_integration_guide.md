# Obstackd Integration Guide

## Overview

This guide explains how the home automation platform integrates with Obstackd, an external observability stack that provides production-ready monitoring, tracing, and metrics collection.

## Architecture Decision

### Why External Observability Stack?

**Separation of Concerns:**
- Observability infrastructure has a different lifecycle than application services
- Single observability stack can monitor multiple application deployments
- Easier to maintain, upgrade, and scale independently
- Follows microservices and platform engineering best practices

**Production Benefits:**
- Obstackd is designed for production from day one
- Zero manual configuration steps (true GitOps)
- Battle-tested component versions
- Vendor-neutral using OpenTelemetry standards

## Integration Points

### 1. Network Integration

The home automation services connect to Obstackd via Docker network:

```yaml
networks:
  obstackd:
    external: true
    name: obstackd_default
```

**Key Points:**
- Uses external network to connect to Obstackd containers
- Services join both internal networks and Obstackd network
- Allows secure communication without exposing ports unnecessarily

### 2. OpenTelemetry Sidecar

A local OTel Collector acts as a sidecar, collecting metrics from services and forwarding to Obstackd:

**Responsibilities:**
- Receive OTLP telemetry from instrumented applications
- Scrape Prometheus exporters (postgres_exporter, node_exporter, cadvisor)
- Enrich telemetry with resource attributes
- Batch and forward to Obstackd OTel Collector

**Configuration:** `otel-sidecar-config.yaml`

```yaml
receivers:
  otlp:
    protocols:
      grpc: 0.0.0.0:4317
      http: 0.0.0.0:4318
  prometheus:
    config:
      scrape_configs:
        - job_name: 'homeassistant'
        - job_name: 'postgres-exporter'
        - job_name: 'cadvisor'

exporters:
  otlp:
    endpoint: otel-collector:4317  # Obstackd collector
```

### 3. Service Instrumentation

Services are configured to send telemetry via environment variables:

```yaml
environment:
  - OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
  - OTEL_SERVICE_NAME=homeassistant
  - OTEL_RESOURCE_ATTRIBUTES=service.namespace=home-automation
```

**Automatic Instrumentation:**
- Applications auto-detect OTLP endpoint
- No code changes required for basic telemetry
- Custom instrumentation can be added per service

### 4. Metrics Exporters

Specialized exporters provide deep insights:

- **postgres_exporter** → Database metrics (connections, queries, performance)
- **node_exporter** → Host system metrics (CPU, memory, disk, network)
- **cadvisor** → Container metrics (resource usage per container)

All exporters are scraped by the OTel sidecar and metrics forwarded to Prometheus.

## Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│                  Application Services                        │
│  (Home Assistant, Music Assistant, EMHASS, etc.)            │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │ OTLP (4317/4318)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│              OpenTelemetry Sidecar Collector                 │
│  - Receives OTLP from apps                                   │
│  - Scrapes Prometheus exporters                              │
│  - Enriches with metadata                                    │
│  - Batches telemetry                                         │
└────────────────────────┬────────────────────────────────────┘
                         │
                         │ OTLP (4317)
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                 Obstackd: OTel Collector                     │
│  - Receives from multiple sources                            │
│  - Routes metrics/traces/logs                                │
└─────┬──────────────────────────────────────┬────────────────┘
      │                                      │
      │ Metrics                              │ Traces
      ▼                                      ▼
┌─────────────┐                        ┌──────────┐
│ Prometheus  │                        │  Tempo   │
└──────┬──────┘                        └────┬─────┘
       │                                    │
       │              ┌─────────────────────┘
       │              │
       ▼              ▼
   ┌──────────────────────┐
   │      Grafana         │
   │  Unified Dashboard   │
   └──────────────────────┘
```

## Deployment Sequence

### Automated (Recommended)

```bash
make ci-pipeline
```

This automatically:
1. Clones Obstackd if not present
2. Creates required directories
3. Starts Obstackd stack
4. Waits for services to be healthy
5. Starts home automation services
6. Connects services to Obstackd network
7. Verifies telemetry pipeline

### Manual Step-by-Step

```bash
# 1. Setup Obstackd
make obstackd-setup

# 2. Start Obstackd services
make obstackd-start

# 3. Verify Obstackd health
cd obstackd
docker compose ps

# 4. Test Obstackd pipeline
./tests/acceptance/observability-pipeline/test-otel-pipeline.sh

# 5. Start home automation services
cd ..
make up-standalone

# 6. Verify integration
make observability-test
```

## Verification Steps

### 1. Verify Network Connectivity

```bash
# Check that Obstackd network exists
docker network ls | grep obstackd

# Verify services are connected
docker network inspect obstackd_default
```

### 2. Check OTel Collector Health

```bash
# Sidecar collector
curl http://localhost:13133/

# Metrics endpoint
curl http://localhost:8888/metrics | grep otelcol

# Obstackd collector
curl http://localhost:8888/metrics
```

### 3. Verify Metrics in Prometheus

```bash
# Check Prometheus is receiving metrics
curl -s 'http://localhost:9090/api/v1/query?query=up' | jq

# Query specific service metrics
curl -s 'http://localhost:9090/api/v1/query?query=up{job="homeassistant"}' | jq
```

### 4. Check Grafana Datasources

```bash
# List datasources
curl -s -u admin:admin http://localhost:3000/api/datasources | jq

# Should show Prometheus and Tempo configured
```

### 5. View Traces in Tempo

Open Grafana: http://localhost:3000
- Navigate to Explore
- Select Tempo datasource
- Query for service: `homeassistant`

## Configuration Details

### OTel Sidecar Configuration

**Receivers:**
- OTLP gRPC (4317) - For instrumented applications
- OTLP HTTP (4318) - For HTTP-based telemetry
- Prometheus - Scrapes exporters

**Processors:**
- `batch` - Efficient batching before export
- `resource` - Add service metadata
- `memory_limiter` - Prevent OOM
- `filter` - Drop unnecessary metrics
- `attributes` - Enrich with custom attributes

**Exporters:**
- `otlp` - Forward to Obstackd (primary)
- `prometheus` - Direct scraping endpoint (backup)
- `logging` - Debugging

### Prometheus Scrape Configuration

The sidecar scrapes these endpoints:
- `homeassistant:8123/api/prometheus` (30s interval)
- `postgres_exporter:9187` (15s interval)
- `cadvisor:8080` (15s interval)
- `node_exporter:9100` (15s interval)

### Resource Attributes

All telemetry is enriched with:
```yaml
service.namespace: home-automation
deployment.environment: production
host.name: <hostname>
collector.name: otel-sidecar
```

## Troubleshooting

### Problem: Services Can't Reach Obstackd

**Symptoms:**
- Services fail to send telemetry
- Connection refused errors in logs

**Solution:**
```bash
# Verify Obstackd is running
cd obstackd && docker compose ps

# Check network exists
docker network ls | grep obstackd

# Restart services to reconnect
cd .. && docker compose restart
```

### Problem: No Metrics in Prometheus

**Symptoms:**
- Prometheus shows no data
- Queries return empty results

**Diagnosis:**
```bash
# Check OTel sidecar logs
docker compose logs otel_sidecar

# Verify scraping
curl http://localhost:8889/metrics

# Check Prometheus targets
curl http://localhost:9090/api/v1/targets
```

**Solution:**
```bash
# Restart OTel sidecar
docker compose restart otel_sidecar

# Wait 30 seconds for scraping
sleep 30

# Verify metrics
curl 'http://localhost:9090/api/v1/query?query=up'
```

### Problem: Traces Not Appearing in Tempo

**Symptoms:**
- No traces in Grafana Tempo view
- Empty trace queries

**Diagnosis:**
```bash
# Check Tempo health
curl http://localhost:3200/ready

# Verify OTel collector is receiving traces
curl http://localhost:8888/metrics | grep traces
```

**Solution:**
- Ensure applications are instrumented for tracing
- Check OTEL_EXPORTER_OTLP_ENDPOINT is set correctly
- Verify trace sampling rate (may be low for testing)

### Problem: High Memory Usage

**Symptoms:**
- OTel collector consuming excessive memory
- OOM errors

**Solution:**
Adjust memory limiter in `otel-sidecar-config.yaml`:
```yaml
processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 256  # Reduce from 512
    spike_limit_mib: 64  # Reduce from 128
```

## Advanced Configuration

### Custom Dashboards

Create custom Grafana dashboards for your services:

1. Open Grafana: http://localhost:3000
2. Create Dashboard → Add Panel
3. Use Prometheus datasource
4. Example queries:
   ```promql
   # Home Assistant request rate
   rate(homeassistant_http_requests_total[5m])
   
   # Database connection pool
   pg_stat_database_numbackends{datname="homeassistant"}
   
   # Container memory usage
   container_memory_usage_bytes{name="homeassistant"}
   ```

### Add New Services

To add observability to new services:

1. **Add to OTel sidecar scrape config:**
   ```yaml
   - job_name: 'new-service'
     scrape_interval: 30s
     static_configs:
       - targets: ['new-service:9999']
   ```

2. **Instrument application:**
   ```yaml
   environment:
     - OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
     - OTEL_SERVICE_NAME=new-service
   ```

3. **Connect to Obstackd network:**
   ```yaml
   networks:
     - obstackd
   ```

### Adjust Retention Periods

**Prometheus (in Obstackd):**
Edit `obstackd/config/prometheus/prometheus.yaml`:
```yaml
global:
  evaluation_interval: 15s
storage:
  tsdb:
    retention_time: 30d  # Adjust as needed
```

**Tempo (in Obstackd):**
Edit `obstackd/config/tempo/tempo.yaml`:
```yaml
compactor:
  compaction:
    block_retention: 168h  # 7 days, adjust as needed
```

## Performance Tuning

### Reduce Metric Cardinality

Filter high-cardinality metrics in sidecar:
```yaml
processors:
  filter:
    metrics:
      exclude:
        match_type: regexp
        metric_names:
          - .*_bucket  # Remove histogram buckets
```

### Optimize Batching

Increase batch size for high-throughput:
```yaml
processors:
  batch:
    timeout: 30s
    send_batch_size: 2048  # Increased from 1024
```

### Scale Prometheus

For large deployments:
1. Increase Prometheus memory in Obstackd
2. Use recording rules for common queries
3. Consider remote write to long-term storage

## Monitoring the Monitors

Obstackd includes self-monitoring:

**OTel Collector Metrics:**
- `otelcol_process_uptime` - Collector uptime
- `otelcol_receiver_accepted_spans` - Traces received
- `otelcol_receiver_accepted_metric_points` - Metrics received
- `otelcol_exporter_sent_spans` - Traces exported

**View in Grafana:**
```promql
# Collector health
up{job="otel-collector"}

# Receiver throughput
rate(otelcol_receiver_accepted_metric_points[5m])

# Export success rate
rate(otelcol_exporter_sent_spans[5m])
```

## Best Practices

1. **Keep Obstackd Running** - Start Obstackd before application services
2. **Test Telemetry** - Run `make observability-test` after changes
3. **Monitor Collector** - Watch OTel collector metrics for issues
4. **Set Alerts** - Configure Prometheus alerts for service health
5. **Regular Updates** - Keep Obstackd updated with `git pull`
6. **Backup Grafana** - Export dashboards regularly
7. **Resource Limits** - Set appropriate limits on collectors
8. **Network Segmentation** - Use separate networks for security

## Migration from Embedded Stack

If migrating from embedded Prometheus/Grafana:

1. **Export Grafana dashboards** from old stack
2. **Stop embedded observability services**
3. **Start Obstackd:** `make obstackd-start`
4. **Import dashboards** to new Grafana
5. **Update Prometheus queries** if needed (labels may differ)
6. **Remove old volumes** after verification

## References

- **Obstackd Repository**: https://github.com/paruff/Obstackd
- **OpenTelemetry Collector**: https://opentelemetry.io/docs/collector/
- **Prometheus Exporters**: https://prometheus.io/docs/instrumenting/exporters/
- **Grafana Datasources**: https://grafana.com/docs/grafana/latest/datasources/
- **Tempo Tracing**: https://grafana.com/docs/tempo/latest/
