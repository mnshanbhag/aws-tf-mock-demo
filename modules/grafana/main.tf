terraform {
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.7"
    }
  }
}

variable "function_name" {
  description = "Lambda function name to scope CloudWatch queries"
  type        = string
}

# ── CloudWatch datasource ──────────────────────────────────────────────────────
# Points Grafana at LocalStack's CloudWatch endpoint using the docker-compose
# service name "localstack" — Grafana and LocalStack share the same network.
# Credentials are dummy values; LocalStack doesn't validate them.

resource "grafana_data_source" "cloudwatch" {
  type = "cloudwatch"
  name = "LocalStack CloudWatch"
  uid  = "localstack-cw"

  json_data_encoded = jsonencode({
    authType          = "keys"
    defaultRegion     = "eu-west-2"
    endpoint          = "http://localstack:4566"
    logsTimeout       = "30s"
    assumeRoleEnabled = false
  })

  secure_json_data_encoded = jsonencode({
    accessKey = "test"
    secretKey = "test"
  })
}

# ── Dashboard ──────────────────────────────────────────────────────────────────
# Four panels covering the key Lambda signals:
#   1. Invocations (stat)  — how often the function is called
#   2. Errors (stat)       — red when >= 1, green when 0
#   3. Duration (time series) — avg execution time in ms
#   4. Log stream (logs)   — raw CloudWatch Logs from /aws/lambda/<name>
#
# The dashboard is declared as a single jsonencode() call so Terraform
# detects changes and redeploys automatically. In a team setup you'd
# store the JSON as a separate file and load it with templatefile().

locals {
  ds = { type = "cloudwatch", uid = grafana_data_source.cloudwatch.uid }
}

resource "grafana_dashboard" "infra" {
  config_json = jsonencode({
    title         = "Mock AWS Infra — LocalStack"
    uid           = "mits-demo-infra"
    description   = "Lambda metrics and logs from the LocalStack mock environment"
    refresh       = "30s"
    schemaVersion = 39
    time          = { from = "now-1h", to = "now" }
    timezone      = "browser"

    panels = [

      # ── 1. Invocations ────────────────────────────────────────────────────
      {
        id      = 1
        type    = "stat"
        title   = "Invocations (1 h)"
        gridPos = { h = 5, w = 6, x = 0, y = 0 }
        options = {
          colorMode     = "background"
          graphMode     = "area"
          orientation   = "auto"
          reduceOptions = { calcs = ["sum"], fields = "", values = false }
          textMode      = "auto"
        }
        fieldConfig = {
          defaults = {
            color      = { mode = "fixed", fixedColor = "blue" }
            thresholds = { mode = "absolute", steps = [{ color = "blue", value = null }] }
            unit       = "short"
          }
          overrides = []
        }
        targets = [{
          refId      = "A"
          datasource = local.ds
          queryMode  = "Metrics"
          namespace  = "AWS/Lambda"
          metricName = "Invocations"
          dimensions = { FunctionName = var.function_name }
          statistic  = "Sum"
          period     = "60"
          region     = "default"
          matchExact = true
        }]
      },

      # ── 2. Errors ─────────────────────────────────────────────────────────
      {
        id      = 2
        type    = "stat"
        title   = "Errors (1 h)"
        gridPos = { h = 5, w = 6, x = 6, y = 0 }
        options = {
          colorMode     = "background"
          graphMode     = "area"
          orientation   = "auto"
          reduceOptions = { calcs = ["sum"], fields = "", values = false }
          textMode      = "auto"
        }
        fieldConfig = {
          defaults = {
            color = { mode = "thresholds" }
            thresholds = {
              mode  = "absolute"
              steps = [
                { color = "green", value = null },
                { color = "red", value = 1 },
              ]
            }
            unit = "short"
          }
          overrides = []
        }
        targets = [{
          refId      = "A"
          datasource = local.ds
          queryMode  = "Metrics"
          namespace  = "AWS/Lambda"
          metricName = "Errors"
          dimensions = { FunctionName = var.function_name }
          statistic  = "Sum"
          period     = "60"
          region     = "default"
          matchExact = true
        }]
      },

      # ── 3. Duration ───────────────────────────────────────────────────────
      {
        id      = 3
        type    = "timeseries"
        title   = "Duration avg (ms)"
        gridPos = { h = 5, w = 12, x = 12, y = 0 }
        options = {
          tooltip = { mode = "single", sort = "none" }
          legend  = { displayMode = "list", placement = "bottom", showLegend = true }
        }
        fieldConfig = {
          defaults = {
            color  = { mode = "palette-classic" }
            unit   = "ms"
            custom = {
              drawStyle         = "line"
              lineInterpolation = "linear"
              lineWidth         = 2
              fillOpacity       = 10
              showPoints        = "auto"
              spanNulls         = false
              axisPlacement     = "auto"
              axisLabel         = ""
              gradientMode      = "none"
              hideFrom          = { legend = false, tooltip = false, viz = false }
              pointSize         = 5
              scaleDistribution = { type = "linear" }
              thresholdsStyle   = { mode = "off" }
            }
            thresholds = { mode = "absolute", steps = [{ color = "green", value = null }] }
          }
          overrides = []
        }
        targets = [{
          refId      = "A"
          datasource = local.ds
          queryMode  = "Metrics"
          namespace  = "AWS/Lambda"
          metricName = "Duration"
          dimensions = { FunctionName = var.function_name }
          statistic  = "Average"
          period     = "60"
          region     = "default"
          matchExact = true
        }]
      },

      # ── 4. Log stream ─────────────────────────────────────────────────────
      # Shows the raw CloudWatch Logs emitted by the Lambda handler.
      # Each log line is the JSON structured log from handler.py.
      {
        id      = 4
        type    = "logs"
        title   = "Lambda Logs — /aws/lambda/${var.function_name}"
        gridPos = { h = 10, w = 24, x = 0, y = 5 }
        options = {
          dedupStrategy      = "none"
          enableLogDetails   = true
          prettifyLogMessage = true
          showCommonLabels   = false
          showLabels         = false
          showTime           = true
          sortOrder          = "Descending"
          wrapLogMessage     = false
        }
        targets = [{
          refId         = "A"
          datasource    = local.ds
          queryMode     = "Logs"
          logGroupNames = ["/aws/lambda/${var.function_name}"]
          region        = "default"
        }]
      },

    ]
  })

  depends_on = [grafana_data_source.cloudwatch]
}

output "dashboard_url" {
  value = "http://localhost:3000/d/mits-demo-infra"
}
