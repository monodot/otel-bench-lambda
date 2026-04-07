package com.example;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayV2HTTPResponse;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.SpanKind;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.context.Scope;
import io.opentelemetry.instrumentation.awssdk.v2_2.AwsSdkTelemetry;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.autoconfigure.AutoConfiguredOpenTelemetrySdk;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;

import java.util.concurrent.TimeUnit;

/**
 * Variant of AuthzHandler that initialises the OTel SDK programmatically
 * rather than relying on the Java agent layer.
 *
 * AutoConfiguredOpenTelemetrySdk reads the same OTEL_* environment variables
 * as the agent, so Terraform config (exporter, endpoint, service name, etc.)
 * is unchanged from the agent-based configs.
 *
 * The DynamoDB client is wired with AwsSdkTelemetry so that the permissions
 * lookup in AuthzHandler produces a child span attributed with table name,
 * request ID, HTTP status, and other aws.dynamodb.* semantic conventions.
 * This is the library-instrumentation equivalent of what the Java agent does
 * automatically for agent-based configs.
 *
 * forceFlush() is called explicitly after each invocation because Lambda may
 * freeze the execution environment before the async exporter drains its queue.
 *
 * Used by: c16-prog-sdk-java, c17-prog-sdk-snap-java
 */
public class AuthzHandlerProgSdk implements RequestHandler<APIGatewayV2HTTPEvent, APIGatewayV2HTTPResponse> {

    private static final OpenTelemetrySdk otelSdk;
    private static final Tracer tracer;
    private static final AuthzHandler delegate;

    static {
        otelSdk = AutoConfiguredOpenTelemetrySdk.initialize().getOpenTelemetrySdk();
        tracer  = otelSdk.getTracer("authz-function");

        // Wire the DynamoDB client with the OTel AWS SDK interceptor so that
        // lookupPermissions() in AuthzHandler produces a child span that carries
        // aws.dynamodb.* semantic conventions — no agent required.
        DynamoDbClient instrumentedDynamoDb = DynamoDbClient.builder()
                .overrideConfiguration(c -> c.addExecutionInterceptor(
                        AwsSdkTelemetry.create(otelSdk).createExecutionInterceptor()))
                .build();

        delegate = new AuthzHandler(instrumentedDynamoDb);
    }

    @Override
    public APIGatewayV2HTTPResponse handleRequest(APIGatewayV2HTTPEvent event, Context context) {
        Span span = tracer.spanBuilder("authz.handle")
                .setSpanKind(SpanKind.SERVER)
                .startSpan();

        try (Scope ignored = span.makeCurrent()) {
            APIGatewayV2HTTPResponse response = delegate.handleRequest(event, context);
            span.setAttribute("http.response.status_code", response.getStatusCode());
            return response;
        } finally {
            span.end();
            otelSdk.getSdkTracerProvider().forceFlush().join(10, TimeUnit.SECONDS);
        }
    }
}
