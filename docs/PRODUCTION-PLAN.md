# Guided Portfolios Platform - Production Plan

## Product boundary

The platform will implement the Guided Portfolios investor journey and the governance console described in the supplied prototype, while replacing browser-only state with authenticated, server-authoritative services.

## Workstreams

1. Foundation
   - React/Vite application structure
   - Environment configuration
   - TypeScript strictness
   - CI and test scaffolding

2. Identity and authorization
   - Supabase Auth
   - Database-backed roles
   - Row Level Security
   - No client-side role switching as an authority

3. Investor suitability
   - Approved suitability profile
   - Preference questionnaire
   - Deterministic score calculation
   - Risk-band mapping
   - Recommendation eligibility checks

4. Portfolio governance
   - Portfolio master records
   - Versioned portfolio definitions
   - Draft/review/compliance/publish workflow
   - Maker-checker segregation of duties
   - Immutable governance events

5. Projection engine
   - Persisted assumptions
   - Seeded deterministic Monte Carlo runs
   - Stored run metadata and outputs
   - Clear separation between illustrative projection and performance promise

6. Investor experience
   - Portfolio discovery and detail
   - Allocation and holdings
   - Projection
   - Consent where required
   - Confirmation and dashboard
   - Statements and activity

7. Quality and operations
   - Unit/integration tests
   - Auditability
   - Error handling
   - Security checks
   - Documentation

## Explicit prototype issues to remove

- localStorage as authoritative business state
- hard-coded investor/admin role
- browser-only maker-checker enforcement
- client-cleareable audit log
- hard-coded portfolio/dashboard data
- non-reproducible Math.random simulation
- fake statement download
- committed/fallback credentials
- unsupported compliance certification claims

## Delivery principle

No production compliance, regulatory approval, certification, or deployment status will be represented as complete unless independently established outside the codebase.
