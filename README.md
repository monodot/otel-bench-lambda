# AWS Lambda OpenTelemetry instrumentation benchmark

![License](https://img.shields.io/badge/license-Apache%202.0-blue) ![OpenTelemetry](https://img.shields.io/badge/OpenTelemetry-instrumented-blueviolet?logo=opentelemetry) ![AWS Lambda](https://img.shields.io/badge/AWS-Lambda-orange?logo=amazon-aws) ![k6](https://img.shields.io/badge/load%20testing-k6-7D64FF?logo=k6)

Benchmarking the latency cost of adding OpenTelemetry instrumentation to Lambda functions in two different languages, both of them shipping telemetry to an external observability platform, via OTLP.

Includes an optional dashboard for Grafana Cloud, to visualise Grafana Cloud k6 test results and CloudWatch metrics together:

![](./dashboard.jpg)

(light mode rules IDST)

## What it measures

We deploy a mock JWT-validation Lambda function (~25 ms of real work) is deployed in multiple variants, which vary in instrumentation depth, exporter destination, memory allocated, and (for Java) whether SnapStart or Agent Fast Start are enabled. 

The same set of variations are deployed for each active language (if applicable), so you can compare cold-start and warm latencies between different runtimes.

We use [k6](https://k6.io/) to load test each variant, to capture cold-start and warm p50/p99 latencies. The results are tagged by `config` (full function name) and `language` so you can slice any way you like in Grafana.

### Configs

The tests comprise the following scenarios or configurations. Each of them varies in export destination, which signals are enabled, memory, SnapStart and so on:

| #   | Export target                       | OTel Instrumentation                    | Memory      | SnapStart | Java | Python |
|-----|-------------------------------------|-----------------------------------------|-------------|-----------|------|--------|
| c01 | None                                | None                                    | 512 MB      | Off       | ✓    | ✓      |
| c02 | None                                | **Agent loaded, all exporters disabled**| 512 MB      | Off       | ✓    | ✓      |
| c03 | **External OTLP direct**            | Full (Java agent)                       | 512 MB      | Off       | ✓    | ✓      |
| c04 | **Collector Lambda Layer**          | Full (Java agent)                       | 512 MB      | Off       | ✓    | ✓      |
| c05 | **External ECS Collector (in VPC)** | Full (Java agent)                       | 512 MB      | Off       | ✓    | ✓      |
| c06 | Collector Lambda Layer              | **Metrics only** (Java agent)           | 512 MB      | Off       | ✓    | ✓      |
| c07 | Collector Lambda Layer              | **Traces only** (Java agent)            | 512 MB      | Off       | ✓    | ✓      |
| c08 | Collector Lambda Layer              | Full (Java agent)                       | **128 MB**  | Off       | ✓    | ✓      |
| c09 | Collector Lambda Layer              | Full (Java agent)                       | **1024 MB** | Off       | ✓    | ✓      |
| c10 | Collector Lambda Layer              | Full (Java agent)                       | 512 MB      | **On**    | ✓    | —      |
| c11 | **External OTLP direct**            | Full (Java agent)                       | 512 MB      | **On**    | ✓    | —      |
| c12 | Collector Lambda Layer              | **Full (fast startup)** (Java agent)    | 512 MB      | Off       | ✓    | —      |
| c13 | Collector Lambda Layer              | **Full (Java wrapper layer)**           | 512 MB      | Off       | ✓    | —      |
| c14 | Collector Lambda Layer              | Full, fast startup (Java agent)         | 512 MB      | **On**    | ✓    | —      |
| c15 | Collector Lambda Layer              | Full (Java wrapper layer)               | 512 MB      | **On**    | ✓    | —      |
| c16 | **Collector Lambda Layer**          | **Full (programmatic SDK)**             | 512 MB      | Off       | ✓    | —      |
| c17 | Collector Lambda Layer              | Full (programmatic SDK)                 | 512 MB      | **On**    | ✓    | —      |
| c19 | Collector Lambda Layer              | **Selective (Lambda + SDK only)**       | 512 MB      | Off       | ✓    | —      |

Notes:

- c01 and c02 exist to establish a baseline. c02 loads the Java/Python agent but sets all exporters to `none`, isolating the cost of agent initialisation from the cost of exporting telemetry.
- c16 and c17 use a programmatic OTel SDK initialisation (no agent layer). c17 still drops ~20% of traces on the first invocation after each SnapStart restore, because the OTLP exporter's TCP connection is stale at that point.
- c19 uses the Java agent but disables all auto-instrumentation by default (`OTEL_INSTRUMENTATION_COMMON_DEFAULT_ENABLED=false`), re-enabling only `OTEL_INSTRUMENTATION_AWS_LAMBDA_ENABLED` and `OTEL_INSTRUMENTATION_AWS_SDK_ENABLED`. Directly comparable to c04 — tests whether pruning unused instrumentations reduces cold-start overhead.
- All Java configs perform a DynamoDB `GetItem` (permissions lookup by JWT subject) on every invocation. For agent-based configs the Java agent instruments this automatically, producing a `aws.dynamodb` child span. For c16/c17 the OTel AWS SDK v2 library instrumentation is wired in manually via an execution interceptor.
- For Java: _Fast startup_ refers to the `OTEL_JAVA_AGENT_FAST_STARTUP_ENABLED` setting. _Java Wrapper_ refers to using the wrapper Lambda layer (instead of the Java Agent Lambda layer).

## Prerequisites

- [AWS CLI](https://aws.amazon.com/cli/) configured with credentials for your target account
- Terraform >= 1.5
- Java 21 + Maven (required to build the Java function)
- Python 3.13 + zip (required to build the Python function)
- [k6](https://k6.io/)
- An external OTLP endpoint, to ship telemetry signals to. If you don't have access to one, you can deploy https://github.com/grafana/docker-otel-lgtm somewhere accessible by the function (not in scope for this repo)
- Grafana Cloud account (optional) - if you want to visualise the k6 test results and CloudWatch metrics together

## Deploy the function variants

### 1. Build the Lambda functions

Build the artifacts for the languages you intend to deploy before running Terraform. Terraform reads the built artifacts directly and will fail if they don't exist.

**Java:**

> Maven Wrapper was added to this project using `mvn wrapper:wrapper`.

```bash
cd functions/java
./mvnw package -q
```

It may produce a warning like _"a terminally deprecated method has been called"_, but you can safely ignore that.

**Python:**

```bash
cd functions/python
./build.sh
```

### 2. Configure Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set deploy_java/deploy_python and fill in layer ARNs
```

- Set `otlp_endpoint`, `otlp_username`, `otlp_password` to the URL, HTTP basic auth username and password of your external observability platform
- Set `deploy_java = true` and/or `deploy_python = true` to control which language variants are deployed. You only need to provide layer ARNs for the languages you are deploying.
- If you want to use the included Grafana dashboard to visualise k6 and CloudWatch metrics, set `create_grafana_iam_user = true` to create a user so that Grafana can query your metrics.

### 3. Authenticate to AWS and apply

```bash
aws sso login --sso-session SESSION

export AWS_PROFILE=...
```

Then apply Terraform config:

```bash
terraform -chdir=terraform init
terraform -chdir=terraform apply
```

## Test the function variants

To test the function variants, use k6. You have the option of running it in three different modes:

- `k6 run`: k6 will test the services from your local machine, and save the results locally. Then you can inspect and interpret the results written to a CSV file. 
- `k6 cloud run --local-execution`: k6 will test the services from your local machine, and write results to Grafana Cloud k6.
- `k6 cloud run`: k6 will upload the test to Grafana Cloud, run completely in the cloud and write the results to Grafana Cloud k6. 

Use one of the `k6 cloud run` options if you want to use the dashboard in this repo, and view the test results alongside your CloudWatch metrics.

### Run load tests locally

You can run the included load tests entirely locally. Here's the command to just run the baseline (uninstrumented) tests for Java and Python:

```bash
k6 run \
  --env NAME_PREFIX=$(terraform -chdir=terraform output -raw name_prefix) \
  --env C01_BASELINE_JAVA_URL=$(terraform -chdir=terraform output -raw config_01_java_url) \
  --env C01_BASELINE_PYTHON_URL=$(terraform -chdir=terraform output -raw config_01_python_url) \
  k6/benchmark-with-scenarios.js
```

(To see the command to run all tests, scroll a bit further below, and omit the `cloud` subcommand.)

Each run produces CSV output in `k6/results/`. You may also consider streaming the results to your own database (e.g. Prometheus) using k6's different outputs - [see the k6 docs for more info](https://grafana.com/docs/k6/latest/get-started/results-output/).

### Run load tests in Grafana Cloud k6

You can run this test entirely within [Grafana Cloud's free tier](https://grafana.com/auth/sign-up). k6 usage is measured in VUh (virtual user-hours), and these tests fall within the included free usage. Most of these commands give an estimate of the cost of running the test, measured in VUh.

Head to your Grafana Cloud instance > Testing and synthetics > Performance > Settings and grab your **Personal API token**, then:

```bash
k6 cloud login -t TOKEN --stack SLUG
```

#### All tests

Run the benchmark test for all Java configs (30m duration, 40 VUh approx.):

```bash
k6 cloud run \
  --env NAME_PREFIX=$(terraform -chdir=terraform output -raw name_prefix) \
  --env C01_BASELINE_JAVA_URL=$(terraform -chdir=terraform output -raw config_01_java_url) \
  --env C02_AGENT_NOOP_JAVA_URL=$(terraform -chdir=terraform output -raw config_02_java_url) \
  --env C03_DIRECT_JAVA_URL=$(terraform -chdir=terraform output -raw config_03_java_url) \
  --env C04_COL_LAYER_JAVA_URL=$(terraform -chdir=terraform output -raw config_04_java_url) \
  --env C05_EXT_COL_JAVA_URL=$(terraform -chdir=terraform output -raw config_05_java_url) \
  --env C06_METRICS_JAVA_URL=$(terraform -chdir=terraform output -raw config_06_java_url) \
  --env C07_TRACES_JAVA_URL=$(terraform -chdir=terraform output -raw config_07_java_url) \
  --env C08_128MB_JAVA_URL=$(terraform -chdir=terraform output -raw config_08_java_url) \
  --env C09_1024MB_JAVA_URL=$(terraform -chdir=terraform output -raw config_09_java_url) \
  --env C10_SNAPSTART_JAVA_URL=$(terraform -chdir=terraform output -raw config_10_java_url) \
  --env C11_DIRECT_SNAP_JAVA_URL=$(terraform -chdir=terraform output -raw config_11_java_url) \
  --env C12_FAST_STARTUP_JAVA_URL=$(terraform -chdir=terraform output -raw config_12_java_url) \
  --env C13_JAVA_WRAPPER_JAVA_URL=$(terraform -chdir=terraform output -raw config_13_java_url) \
  --env C14_FAST_SNAP_JAVA_URL=$(terraform -chdir=terraform output -raw config_14_java_url) \
  --env C15_WRAPPER_SNAP_JAVA_URL=$(terraform -chdir=terraform output -raw config_15_java_url) \
  --env C16_PROG_SDK_JAVA_URL=$(terraform -chdir=terraform output -raw config_16_java_url) \
  --env C17_PROG_SDK_SNAP_JAVA_URL=$(terraform -chdir=terraform output -raw config_17_java_url) \
  --env C19_SELECTIVE_INSTR_JAVA_URL=$(terraform -chdir=terraform output -raw config_19_java_url) \
  k6/benchmark-with-scenarios.js
```

Run the benchmark test for all Python configs (18m duration, 24 VUh approx.):

```bash
k6 cloud run \
  --env NAME_PREFIX=$(terraform -chdir=terraform output -raw name_prefix) \
  --env C01_BASELINE_PYTHON_URL=$(terraform -chdir=terraform output -raw config_01_python_url) \
  --env C02_AGENT_NOOP_PYTHON_URL=$(terraform -chdir=terraform output -raw config_02_python_url) \
  --env C03_DIRECT_PYTHON_URL=$(terraform -chdir=terraform output -raw config_03_python_url) \
  --env C04_COL_LAYER_PYTHON_URL=$(terraform -chdir=terraform output -raw config_04_python_url) \
  --env C05_EXT_COL_PYTHON_URL=$(terraform -chdir=terraform output -raw config_05_python_url) \
  --env C06_METRICS_PYTHON_URL=$(terraform -chdir=terraform output -raw config_06_python_url) \
  --env C07_TRACES_PYTHON_URL=$(terraform -chdir=terraform output -raw config_07_python_url) \
  --env C08_128MB_PYTHON_URL=$(terraform -chdir=terraform output -raw config_08_python_url) \
  --env C09_1024MB_PYTHON_URL=$(terraform -chdir=terraform output -raw config_09_python_url) \
  k6/benchmark-with-scenarios.js
```

#### Basic cross-language comparison

Run a cross-language comparison (just the baseline and full-instrumentation configs) (9m duration, 10 VUh approx.):

```bash
k6 cloud run \
  --env NAME_PREFIX=$(terraform -chdir=terraform output -raw name_prefix) \
  --env C01_BASELINE_JAVA_URL=$(terraform -chdir=terraform output -raw config_01_java_url) \
  --env C04_COL_LAYER_JAVA_URL=$(terraform -chdir=terraform output -raw config_04_java_url) \
  --env C01_BASELINE_PYTHON_URL=$(terraform -chdir=terraform output -raw config_01_python_url) \
  --env C04_COL_LAYER_PYTHON_URL=$(terraform -chdir=terraform output -raw config_04_python_url) \
  k6/benchmark-with-scenarios.js
```

#### More example setups

<details>
<summary>Just the SnapStart variants</summary>

```shell
k6 cloud run \
  --env NAME_PREFIX=$(terraform -chdir=terraform output -raw name_prefix) \
  --env C10_SNAPSTART_JAVA_URL=$(terraform -chdir=terraform output -raw config_10_java_url) \
  --env C11_DIRECT_SNAP_JAVA_URL=$(terraform -chdir=terraform output -raw config_11_java_url) \
  --env C14_FAST_SNAP_JAVA_URL=$(terraform -chdir=terraform output -raw config_14_java_url) \
  --env C15_WRAPPER_SNAP_JAVA_URL=$(terraform -chdir=terraform output -raw config_15_java_url) \
  --env C17_PROG_SDK_SNAP_JAVA_URL=$(terraform -chdir=terraform output -raw config_17_java_url) \
  k6/benchmark-with-scenarios.js
```

</details>

<details>
<summary>Just the programmatic SDK initialisation (with c13 as a baseline as it's got a good balance of reliability and latency)</summary>

```shell
k6 cloud run \
  --env NAME_PREFIX=$(terraform -chdir=terraform output -raw name_prefix) \
  --env C13_JAVA_WRAPPER_JAVA_URL=$(terraform -chdir=terraform output -raw config_13_java_url) \
  --env C16_PROG_SDK_JAVA_URL=$(terraform -chdir=terraform output -raw config_16_java_url) \
  --env C17_PROG_SDK_SNAP_JAVA_URL=$(terraform -chdir=terraform output -raw config_17_java_url) \
  k6/benchmark-with-scenarios.js
```

</details>

<details>
<summary>Comparing regular SnapStart with programmatic SDK SnapStart</summary>

```shell
k6 cloud run \
  --env NAME_PREFIX=$(terraform -chdir=terraform output -raw name_prefix) \
  --env C10_SNAPSTART_JAVA_URL=$(terraform -chdir=terraform output -raw config_10_java_url) \
  --env C17_PROG_SDK_SNAP_JAVA_URL=$(terraform -chdir=terraform output -raw config_17_java_url) \
  k6/benchmark-with-scenarios.js
```

</details>

<details>
<summary>Comparing the standard Collector Layer with the same approach but only selective instrumentation turned on</summary>

```shell
k6 cloud run \
    --env NAME_PREFIX=$(terraform -chdir=terraform output -raw name_prefix) \
    --env C04_COL_LAYER_JAVA_URL=$(terraform -chdir=terraform output -raw config_04_java_url) \
    --env C19_SELECTIVE_INSTR_JAVA_URL=$(terraform -chdir=terraform output -raw config_19_java_url) \
    k6/benchmark-with-scenarios.js
```

</details>

### Run load tests locally but publish results to Grafana Cloud k6

Or, to run locally but publish results to Grafana Cloud k6, use the `--local-execution` flag:

```bash
k6 cloud run --local-execution \
  --env NAME_PREFIX=$(terraform -chdir=terraform output -raw name_prefix) \
  --env C01_BASELINE_JAVA_URL=$(terraform -chdir=terraform output -raw config_01_java_url) \
  --env C01_BASELINE_PYTHON_URL=$(terraform -chdir=terraform output -raw config_01_python_url) \
  k6/benchmark-with-scenarios.js
```

### Test a function manually

You can also send a single test request to each function individually using the AWS CLI:

```bash
aws lambda invoke \
  --region us-east-1 \
  --function-name otel-bench-c01-baseline-java \
  --payload '{}' /tmp/lambda-response.json 2>&1 && cat /tmp/lambda-response.json
```

And for Python:

```bash
aws lambda invoke \
  --region us-east-1 \
  --function-name otel-bench-c01-baseline-python \
  --payload '{}' /tmp/lambda-response.json 2>&1 && cat /tmp/lambda-response.json
```

Test a Python function which ships directly via OTLP:

```bash
aws lambda invoke \
  --region us-east-1 \
  --function-name otel-bench-c03-direct-python \
  --payload '{}' /tmp/lambda-response.json 2>&1 && cat /tmp/lambda-response.json
```

## Interpret the test results

### Locally

If you've run the tests entirely locally, then you'll find a CSV of results inside `k6/results` which includes metrics for latency of cold vs warm requests, passing/failing requests and so on.

Example first few lines of the results CSV:

```csv
config,language,metric,stat,value
otel-bench-c01-baseline-java,java,cold_start_duration_ms,med,1457.831732
otel-bench-c01-baseline-java,java,cold_start_duration_ms,max,1737.849357
otel-bench-c01-baseline-java,java,cold_start_duration_ms,p(90),1684.9525899999999
otel-bench-c01-baseline-java,java,cold_start_duration_ms,p(95),1728.3153255
otel-bench-c01-baseline-java,java,cold_start_duration_ms,p(99),1735.9425507
otel-bench-c01-baseline-java,java,cold_start_duration_ms,count,16
otel-bench-c01-baseline-java,java,cold_start_duration_ms,avg,1413.679725
otel-bench-c01-baseline-java,java,cold_start_duration_ms,min,647.774205
...
```

### Visualise test results & CloudWatch metrics in Grafana Cloud (optional)

This repo includes a dashboard which visualises the Grafana Cloud k6 test results and CloudWatch Lambda metrics side-by-side, so that you can compare how each scenario impacts both the client experience and your infrastructure metrics.

**NOTE: To see the test results in Grafana Cloud, you will need to run the load tests using `k6 cloud run` or `k6 cloud run --local-execution`.**

#### Set up AWS CloudWatch data source

All functions have CloudWatch Lambda Insights enabled. Metrics are available in
CloudWatch under the `LambdaInsights` namespace, so we'll set up the CloudWatch
data source in Grafana.

Get the generated access key and secret:

```bash
terraform -chdir=terraform output -raw grafana_cloudwatch_access_key_id
terraform -chdir=terraform output -raw grafana_cloudwatch_secret
```

In Grafana:

1. Go to **Connections → Data sources → Add data source → CloudWatch**.
2. Set **Authentication provider** to `Access & secret key`.
3. Paste the **Access key ID** and **Secret access key** from the Terraform outputs above.
4. Set **Default region** to `us-east-1`.
5. Click **Save & test** — you should see "Data source is working".

#### Install the dashboard

Upload the sample dashboard (`./dashboard.json`) to your Grafana Cloud instance.

#### Use the dashboard

Open the dashboard, then:

- Select your CloudWatch data source from the variable dropdowns
- Select your k6 Project, test and test run to see correlated client-side request metrics. 

## Architecture

### Lambda Layer collector

Configs c04, c06, c07, c08, c09, c10, c16, c17 (Java) and c04, c06, c07, c08, c09 (Python)
use the OTel Collector running as a Lambda Extension (via the ADOT collector
layer). The function sends OTLP HTTP to `localhost:4318`; the extension forwards
to Grafana Cloud.


### DynamoDB permissions table

All Java configs perform a `GetItem` on the `{name_prefix}-permissions` table to look up roles for the JWT subject on every invocation. This produces a realistic child span in every trace.

For **agent-based configs** (c02–c15, c19) the Java agent instruments `DynamoDbClient` automatically via bytecode injection — no code changes required. For **programmatic SDK configs** (c16, c17) `AuthzHandlerProgSdk` wires the OTel AWS SDK v2 execution interceptor (`AwsSdkTelemetry.create(otelSdk).createExecutionInterceptor()`) into the client at initialisation time, producing equivalent `aws.dynamodb.*` span attributes without the agent.

### External ECS collector

Config c05 deploys a standalone `otel/opentelemetry-collector-contrib` container
on ECS Fargate behind a Network Load Balancer. The Lambda sends OTLP HTTP to
the NLB's public DNS. This models the pattern where customers run their own
internal collectors before pushing to an external observability platform.

### Python instrumentation

Python configs use the AWS ADOT Python Lambda layer, which injects
instrumentation via `AWS_LAMBDA_EXEC_WRAPPER=/opt/otel-instrument`. The
function code itself has no OTel imports — instrumentation is entirely
layer-controlled, mirroring how the Java ADOT agent works.

## Status

Check what's actually deployed:

```bash
aws sso login --sso-session SESSION
export AWS_PROFILE=...
terraform -chdir=terraform state list
```

## Teardown

```bash
terraform -chdir=terraform destroy
```

## Architectural decisions

- **k6 tests are organised into scenarios:** so we can view all the results using a single query on a dashboard
- **each k6 scenario runs in sequence:** so that we avoid any doubt around resource contention between Lambda functions (there shouldn't be any, but this just makes sure of it)
- **language tag on every metric:** enables cross-language comparison in Grafana without needing separate test runs

## Sample results

This test was run on **2026-04-06**. All durations are p95, measured by k6 from the client side.

| #   | Config                             | Cold Start P95 — Java | Warm P95 — Java | Cold Start P95 — Python | Warm P95 — Python |
|-----|------------------------------------|-----------------------|-----------------|-------------------------|-------------------|
| c01 | Baseline (no instrumentation)      | 1,730 ms              | 54.0 ms         | 322 ms                  | 52.5 ms           |
| c02 | Agent loaded, no export            | 5,920 ms              | 54.5 ms         | 1,570 ms                | 53.8 ms           |
| c03 | Direct OTLP export                 | 9,440 ms              | 668 ms          | 3,060 ms                | 1,260 ms          |
| c04 | Collector Lambda Layer             | 7,910 ms              | 78.8 ms         | 2,270 ms                | 59.6 ms           |
| c05 | External ECS Collector (VPC)       | 7,500 ms              | 206 ms          | 1,840 ms                | 105 ms            |
| c06 | Metrics only (Collector Layer)     | 7,680 ms              | 67.6 ms         | 2,200 ms                | 56.1 ms           |
| c07 | Traces only (Collector Layer)      | 7,520 ms              | 60.9 ms         | 2,190 ms                | 56.8 ms           |
| c08 | 128 MB memory (Collector Layer)    | TIMEOUT               | TIMEOUT         | 4,380 ms                | 291 ms            |
| c09 | 1024 MB memory (Collector Layer)   | 6,860 ms              | 59.4 ms         | 2,220 ms                | 58.6 ms           |
| c10 | SnapStart (Collector Layer)        | 3,540 ms              | 73.2 ms         | n/a                     | n/a               |
| c11 | SnapStart + Direct OTLP            | 5,000 ms              | 672 ms          | n/a                     | n/a               |
| c12 | Agent Fast Start (Collector Layer) | 7,500 ms              | 77.3 ms         | n/a                     | n/a               |
| c13 | Java Wrapper (Collector Layer)     | 4,370 ms              | 69.1 ms         | n/a                     | n/a               |
| c14 | Agent Fast Start + SnapStart       | 3,720 ms              | 70.7 ms         | n/a                     | n/a               |
| c15 | Java Wrapper + SnapStart           | 3,230 ms              | 68.1 ms         | n/a                     | n/a               |
| c16 | Programmatic SDK (no SnapStart)    | —                     | —               | n/a                     | n/a               |
| c17 | Programmatic SDK + SnapStart       | —                     | —               | n/a                     | n/a               |
| c19 | Selective instrumentation (Agent)  | —                     | —               | n/a                     | n/a               |

### Summary of findings

- Python is far more performant than Java
- Direct export to an external OTLP endpoint (without a collector) is often the slowest
- Placing a Lambda in a VPC (so it can access a private otel-collector instance) can add latency to cold start times, due to the work required in setting up the network interface. [See Yan Cui's blog.](https://theburningmonk.com/2018/01/im-afraid-youre-thinking-about-aws-lambda-cold-starts-all-wrong/) 
- Setting memory to an artificially low value (e.g. 128Mb) slows down performance. So, don't do that :)
- SnapStart seems to have an impact on zero-code (agent/wrapper) instrumentation. If using SnapStart, it's better to initialise the SDK manually.
