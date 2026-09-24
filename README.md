# Guided Portfolios Platform

Production-oriented guided investing workspace for EmCoin.

## Stack
- React + Vite + TypeScript
- Supabase Auth + PostgreSQL + Row Level Security
- Deterministic Monte Carlo projection engine
- Database-backed portfolio governance and maker-checker controls

## Local setup
1. Copy `.env.example` to `.env.local`.
2. Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`.
3. Install dependencies with `npm install`.
4. Run `npm run dev`.

## Database
Migrations live under `supabase/migrations`. The production schema includes investor suitability, portfolio versions, holdings, benchmarks, requests, transactions, statements, simulations, and immutable governance events.

## Security boundary
The browser is never the authority for roles or governance transitions. Authorization is enforced by Supabase Auth, PostgreSQL RLS, and protected workflow functions.

This repository does not claim regulatory approval, certification, or production compliance status.

## Deployment verification
Production deployments are sourced from the `main` branch through the connected Vercel project.
