# Pre-built Keycloak image for production (`start --optimized`).
# Bakes in the scripts feature + the Azul Tech domain-guard provider so the
# runtime container starts fast and doesn't re-run the build step.

FROM quay.io/keycloak/keycloak:20.0.5 AS builder
ENV KC_DB=postgres
ENV KC_FEATURES=scripts
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true

COPY providers/azul-domain-guard.jar /opt/keycloak/providers/
RUN /opt/keycloak/bin/kc.sh build

FROM quay.io/keycloak/keycloak:20.0.5
COPY --from=builder /opt/keycloak/ /opt/keycloak/
ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
