/**
 * k6 multi-config benchmark for the AWS Lambda OTel overhead matrix.
 *
 * Scenarios are built dynamically: only configs whose URL env var is set are
 * included. Run all 11, or just one or two — the timing offsets adjust automatically.
 *
 * Usage (all configs):
 *   NAME_PREFIX=$(terraform -chdir=terraform output -raw name_prefix) \
 *   C1_BASELINE_URL=$(terraform -chdir=terraform output -raw config_1_url) \
 *   C2_SDK_URL=$(terraform -chdir=terraform output -raw config_2_url) \
 *   ... \
 *   k6 run k6/benchmark-with-scenarios.js
 *
 * Usage (subset):
 *   NAME_PREFIX=$(terraform -chdir=terraform output -raw name_prefix) \
 *   C1_BASELINE_URL=$(terraform -chdir=terraform output -raw config_1_url) \
 *   C4_COL_LAYER_URL=$(terraform -chdir=terraform output -raw config_4_url) \
 *   k6 run k6/benchmark-with-scenarios.js
 *
 * NAME_PREFIX must match the Terraform name_prefix variable (default: otel-bench).
 * It tags each k6 result with the same service name the Lambda function reports
 * via OTEL_SERVICE_NAME, enabling cross-correlation in Grafana.
 *
 * Each active config gets a 120 s slot:
 *   +0 s  — burst ramp-up (forces cold starts)
 *   +50 s — warm constant-rate phase begins
 *   +110 s — warm phase ends; 10 s cooldown before the next config
 */

import http from 'k6/http';
import {check} from 'k6';
import {Counter, Trend} from 'k6/metrics';
import tempo from 'https://jslib.k6.io/http-instrumentation-tempo/1.0.0/index.js';

// ── Metrics ────────────────────────────────────────────────────────────────────

const coldStartDuration = new Trend('cold_start_duration_ms', true);
const warmDuration      = new Trend('warm_duration_ms', true);
const coldStartCount    = new Counter('cold_start_count');

// ── Config registry ────────────────────────────────────────────────────────────
// SUFFIXES is the canonical ordered list. To add a new config, add its suffix
// here and the corresponding URL env var is derived automatically.

const NAME_PREFIX = __ENV.NAME_PREFIX || 'otel-bench';

const SUFFIXES = [
    'c1-baseline', 'c2-sdk',      'c3-direct',  'c4-col-layer',   'c5-ext-col',
    'c6-metrics',  'c7-traces',   'c8-128mb',   'c9-1024mb',
    'c10-snapstart', 'c11-direct-snap',
];

// c1-baseline → C1_BASELINE_URL
function suffixToEnvVar(suffix) {
    return suffix.toUpperCase().replace(/-/g, '_') + '_URL';
}

function cfg(suffix) {
    return `${NAME_PREFIX}-${suffix}`;
}

// Only include configs whose URL was provided. Order is preserved from SUFFIXES.
const ACTIVE_SUFFIXES = SUFFIXES.filter(s => !!__ENV[suffixToEnvVar(s)]);
const ACTIVE_CONFIGS  = ACTIVE_SUFFIXES.map(cfg);

// ── Scenario builder ───────────────────────────────────────────────────────────
// Timing offsets are recalculated based on the active set, so running a subset
// produces a test that is just as short as it needs to be.

function buildScenarios() {
    const scenarios = {};
    ACTIVE_SUFFIXES.forEach((suffix, i) => {
        const burstStart = i * 120;
        const warmStart  = burstStart + 50;
        const url        = __ENV[suffixToEnvVar(suffix)] || '';
        const configName = cfg(suffix);
        const key        = suffix.replace(/-/g, '_');

        scenarios[`${key}_burst`] = {
            executor:         'ramping-vus',
            startTime:        `${burstStart}s`,
            startVUs:         1,
            stages: [
                {duration: '10s', target: 50},
                {duration: '20s', target: 50},
                {duration: '10s', target: 0},
            ],
            gracefulRampDown: '5s',
            env: {FUNCTION_URL: url, CONFIG_NAME: configName},
        };

        scenarios[`${key}_warm`] = {
            executor:        'constant-arrival-rate',
            startTime:       `${warmStart}s`,
            rate:            10,
            timeUnit:        '1s',
            duration:        '60s',
            preAllocatedVUs: 15,
            maxVUs:          30,
            env: {FUNCTION_URL: url, CONFIG_NAME: configName},
        };
    });
    return scenarios;
}

// ── Threshold builder ──────────────────────────────────────────────────────────

function buildThresholds() {
    const t = {http_req_failed: ['rate<0.01']};
    for (const name of ACTIVE_CONFIGS) {
        t[`cold_start_duration_ms{config:${name}}`] = [];
        t[`cold_start_count{config:${name}}`]       = [];
        // c8-128mb always times out — exclude from the warm latency SLO.
        if (!name.endsWith('c8-128mb')) {
            t[`warm_duration_ms{config:${name}}`] = ['p(99)<5000'];
        }
    }
    return t;
}

// ── Options ────────────────────────────────────────────────────────────────────

export const options = {
    scenarios:          buildScenarios(),
    thresholds:         buildThresholds(),
    summaryTrendStats:  ['avg', 'min', 'med', 'max', 'p(90)', 'p(95)', 'p(99)', 'count'],
    cloud: {
        name: 'Lambda OTel Benchmark — all configs',
    },
};

// ── Shared request payload ─────────────────────────────────────────────────────

const PAYLOAD = JSON.stringify({
    token: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
         + '.eyJzdWIiOiJiZW5jaC11c2VyIiwiaWF0IjoxNzAwMDAwMDAwLCJleHAiOjk5OTk5OTk5OTl9'
         + '.mock-signature-not-verified',
});

const HEADERS = {'Content-Type': 'application/json'};

// ── Enable Tempo tracing (in Cloud) ────────────────────────────────────────────

tempo.instrumentHTTP({
    // possible values: "w3c", "jaeger"
    propagator: 'w3c',
});

// ── Default function ───────────────────────────────────────────────────────────

export default function () {
    if (!__ENV.FUNCTION_URL) return;

    const configName = __ENV.CONFIG_NAME;

    const res = http.post(__ENV.FUNCTION_URL, PAYLOAD, {
        headers: HEADERS,
        timeout: '30s',
        tags:    {config: configName},
    });

    const ok = check(res, {
        'status 200 or 403': (r) => r.status === 200 || r.status === 403,
    }, {config: configName});

    if (!ok) return;

    let body;
    try {
        body = JSON.parse(res.body);
    } catch (_) {
        return;
    }

    const tags = {config: configName};
    if (body.coldStart === true) {
        coldStartDuration.add(res.timings.duration, tags);
        coldStartCount.add(1, tags);
    } else {
        warmDuration.add(res.timings.duration, tags);
    }
}

// ── Summary ────────────────────────────────────────────────────────────────────

export function handleSummary(data) {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    const csvPath   = `k6/results/all-configs-${timestamp}.csv`;

    return {
        stdout:    buildTextSummary(data),
        [csvPath]: toCsv(data),
    };
}

function buildTextSummary(data) {
    const colW    = Math.max(...ACTIVE_CONFIGS.map(c => c.length), 6);
    const pad     = (s, w) => String(s ?? 'n/a').padStart(w);
    const header  = `${'Config'.padEnd(colW)}  ${pad('Cold #', 8)}  ${pad('C p50', 8)}  ${pad('C p99', 8)}  ${pad('W p50', 8)}  ${pad('W p99', 8)}  ${pad('W reqs', 8)}`;
    const divider = '-'.repeat(header.length);

    const lines = ['', '=== Lambda OTel Benchmark — Results ===', '', header, divider];

    for (const name of ACTIVE_CONFIGS) {
        lines.push(
            `${name.padEnd(colW)}  ` +
            `${pad(mv(data, `cold_start_count{config:${name}}`,       'count'), 8)}  ` +
            `${pad(mv(data, `cold_start_duration_ms{config:${name}}`, 'med'),   8)}  ` +
            `${pad(mv(data, `cold_start_duration_ms{config:${name}}`, 'p(99)'), 8)}  ` +
            `${pad(mv(data, `warm_duration_ms{config:${name}}`,       'med'),   8)}  ` +
            `${pad(mv(data, `warm_duration_ms{config:${name}}`,       'p(99)'), 8)}  ` +
            `${pad(mv(data, `warm_duration_ms{config:${name}}`,       'count'), 8)}`
        );
    }

    lines.push(divider, '(all durations in ms)', '');
    return lines.join('\n');
}

function mv(data, metricName, stat) {
    const m = data.metrics[metricName];
    if (!m) return 'n/a';
    const v = m.values[stat];
    return v !== undefined ? Math.round(v) : 'n/a';
}

function toCsv(data) {
    const rows = ['config,metric,stat,value'];
    for (const [name, metric] of Object.entries(data.metrics)) {
        for (const [stat, value] of Object.entries(metric.values)) {
            rows.push(`,${name},${stat},${value}`);
        }
    }
    return rows.join('\n') + '\n';
}