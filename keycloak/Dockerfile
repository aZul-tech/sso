# Pre-built Keycloak image for production (`start --optimized`).
#
# NOTE: this used to also bake in the "scripts" feature + the Azul Tech
# domain-guard provider (keycloak/providers-src/) for the Zoho-broker design.
# That design was replaced — Keycloak is its own IdP now (see
# docs/HANDOFF-TO-IT.md, docs/PHASE-1-REALM.md) — configure-realm.sh never
# wires the domain-guard into any flow, so it's dead code. Pinning to the
# actual runtime image (26.7.3, matching docker-compose.yml) instead of the
# stale EOL 20.0.5 this Dockerfile was still building.
FROM quay.io/keycloak/keycloak:26.7.3 AS builder
ENV KC_DB=postgres
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true

RUN /opt/keycloak/bin/kc.sh build

FROM quay.io/keycloak/keycloak:26.7.3
COPY --from=builder /opt/keycloak/ /opt/keycloak/
ENTRYPOINT ["/opt/keycloak/bin/kc.sh"]
