# Security Policy — MCP (Managed Control Platform)

This document describes the security policy for MCP, including supported versions, reporting channels, scope, and operational best practices.

<p align="center">
  🇬🇧 <strong>English</strong> · 🇩🇪 <a href="SECURITY_de.md">Deutsch</a> · 🇸🇦 <a href="SECURITY_ar.md">العربية</a>
</p>

---

## Supported Versions

Security fixes are provided according to the following policy:

| Version | Supported | Notes |
| ------- | --------- | ----- |
| 7.x (AI-Enhanced) | ✅ | Current — actively maintained (Beta) |
| 6.x | ✅ | Security patches only (no new features) |
| 5.x | ❌ | End of life — upgrade recommended |
| < 5.0 | ❌ | Unsupported — may contain known vulnerabilities |

> **Recommendation:** All deployments should run MCP v7.x to benefit from real-time AI security analysis and predictive threat detection.

---

## Security Architecture (High Level)

MCP follows a defense-in-depth approach. This section is descriptive and not a compliance guarantee — operators remain responsible for secure configuration, access control, and regulatory audits.

### Network Segmentation

5 isolated Docker bridge networks limit the blast radius and enforce least-privilege communication:

| Network | Purpose | Access |
|---------|---------|--------|
| `mcp-edge-net` | Ingress only (Nginx reverse proxy) | External (80/443) |
| `mcp-app-net` | Internal application traffic | Internal only |
| `mcp-data-net` | Databases (PostgreSQL, pgvector, Redis, MariaDB, Elasticsearch) | Authorized DB clients only |
| `mcp-sec-net` | Reserved for security tooling / SIEM extension | Reserved |
| `mcp-ai-net` | AI stack (Ollama, Gateway, Workers) | AI + App only |

### Local AI by Default

All AI processing (Ollama + LangChain) is designed to run 100% on-premise. Data is intended to remain within the operator's infrastructure. No external AI API calls are made by default.

### Identity & Access Control

Keycloak with MFA (TOTP) for all user-facing services. SSO integration available for enterprise environments.

### Secrets Management

Secrets are stored outside version control. Two approaches supported:

- **`.env` with strict file permissions** (`chmod 600`, root-owned) — default
- **OpenBao** (Vault fork) — centralized secrets management for production environments

### TLS Everywhere

Certbot-managed certificates with automatic renewal. TLS 1.2+ enforced at the reverse proxy layer. All inter-service communication within Docker networks is isolated but not encrypted by default (operator may add mTLS if required).

### Host Hardening (Recommended)

- SSH key-only authentication
- UFW firewall (ports 22, 80, 443, 51820 only)
- WireGuard VPN for admin access
- No root login via SSH

### Continuous Security Scanning

Container and host scanning can feed into the AI incident pipeline for automated analysis:

| Tool | Target | Schedule |
|------|--------|----------|
| Trivy | Container images (CVEs) | Daily 05:00 |
| Nuclei | Web surface vulnerabilities | Weekly (Wednesday 05:00) |
| Lynis | Host-level audit | Monthly (1st, 06:00) |
| DIUN | Image update detection | Continuous |

> Scan results are analyzed by the AI pipeline and converted into prioritized tickets with impact assessment. See the [AI Security Analysis](README.md#ai-security-analysis) section in the README.

---

## Reporting a Vulnerability (Coordinated Disclosure)

We take security vulnerabilities seriously. Please report issues privately and responsibly.

### How to Report

- **Email:** security@moustafaalmasri.com
- **Subject:** `[MCP Security] <short description>`
- **Encryption (optional):** PGP encryption is supported (key available upon request).

### What to Include

- MCP version (e.g., 7.x) and environment details (OS, Docker version)
- Clear reproduction steps (PoC preferred)
- Impact assessment (what an attacker gains)
- Mitigation ideas (optional but appreciated)
- Contact information for follow-up

### What NOT to Include

- Real secrets (API keys, passwords, private keys)
- Any customer/production personal data
- Large data dumps or full database exports

---

## Response Targets

We aim to follow these target timelines (best effort, not a contractual SLA):

| Target Time | Action |
| ----------- | ------ |
| Within 48 hours | Acknowledge receipt |
| Within 7 days | Initial assessment + severity classification |
| Within 30 days | Fix released for confirmed vulnerabilities (where feasible) |
| Upon fix release | Public advisory + credit (unless you prefer anonymity) |

---

## Severity Classification

Severity is assessed based on impact and exploitability (aligned with CVSS methodology):

| Severity | Examples | Target |
| -------- | -------- | ------ |
| **Critical** | RCE, container escape, authentication bypass, data exfiltration at scale | 72 hours |
| **High** | Privilege escalation, AI pipeline manipulation, cross-tenant data access | 7 days |
| **Medium** | Information disclosure, DoS via configuration flaws, lateral movement enablers | 30 days |
| **Low** | Minor information leaks, UI issues, non-exploitable misconfigurations, hardening suggestions | Next scheduled release |

---

## Safe Harbor

We support responsible, good-faith security research.

If you:

- test only within the **Scope** defined below,
- avoid privacy violations, data destruction, and service disruption,
- do not use social engineering,
- and report findings privately,

then we will treat your research as authorized under this policy and will not initiate legal action against you for accidental, non-malicious violations related to your testing.

---

## Scope

### In Scope

- All MCP containers (33 total) and their configurations
- Docker network segmentation (`mcp-edge-net`, `mcp-app-net`, `mcp-data-net`, `mcp-sec-net`, `mcp-ai-net`)
- AI Gateway API (`mcp-ai-gateway`) and the analysis pipeline
- Authentication flows (Keycloak, SSO, MFA)
- n8n workflow automation and webhook endpoints
- Secrets management (OpenBao, `.env` handling)
- TLS/SSL configuration (Nginx, Certbot)
- Backup and restore pipeline (restic)
- Inter-container communication and API token boundaries
- Multi-tenant data isolation (pgvector `tenant_id`, Keycloak realms)

### Out of Scope

- Third-party SaaS integrations not managed by MCP
- Social engineering attacks against personnel
- Physical security of the hosting infrastructure
- Denial of service via volumetric network flooding (infrastructure-level)

---

## Security Best Practices for Operators

### Critical Rules

1. **Never expose the AI Gateway** (`mcp-ai-gateway:8000`) to the public internet — it must only be accessible within `mcp-ai-net` and `mcp-app-net`.
2. **Never commit `.env` or secrets to version control** — restrict file permissions (`chmod 600`, root-owned).

### Operational Security

3. **Rotate all tokens** in `.env` after initial deployment and periodically thereafter. Pay special attention to `ZAMMAD_AI_TOKEN` and `AI_GATEWAY_SECRET`.
4. **Enable MFA** for all Keycloak accounts without exception.
5. **Restrict SSH access** to key-based authentication over WireGuard VPN only.
6. **Monitor AI confidence scores** — alerts with confidence < 50% may indicate adversarial input or data poisoning attempts.
7. **Review AI-generated tickets** before forwarding to clients, especially during the first weeks of deployment (human-in-the-loop).
8. **Keep models updated** — run `ollama pull` periodically to get patched model versions.
9. **Keep container images updated** and monitor CVEs via DIUN + Trivy.
10. **Run the Go-Live Checklist** after every major configuration change (networking, auth, proxy, storage, secrets).

---

## Acknowledgments

We appreciate security researchers who help improve MCP. With your permission, confirmed vulnerabilities will be credited in the changelog and in this section.

---

<p align="center"><em>Security is not a feature — it's the foundation.</em></p>
