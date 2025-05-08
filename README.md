# GVYEO System

A client-side web application for GVYEO, built with React, Vite, and Supabase.

## Project Setup and Deployment

### 1. Clone the Repository (or use the provided code)

If this code is pushed to a GitHub repository, clone it:
```bash
git clone <repository-url>
cd gvyeo-app
```

### 2. Install Dependencies

This project uses `pnpm` for package management. Make sure you have `pnpm` installed.

```bash
cd /path/to/gvyeo-app
pnpm install
```

### 3. Populate `.env` File

Create a `.env` file in the root of the `gvyeo-app` directory by copying the `.env.example` file:

```bash
cp .env.example .env
```

Then, fill in the required environment variables in the `.env` file:

```
VITE_SUPABASE_URL=your_supabase_url
VITE_SUPABASE_ANON_KEY=your_supabase_anon_key
# SUPABASE_SERVICE_KEY=your_supabase_service_role_key (Only if needed for admin operations from backend/scripts, not directly exposed to client)
# PAYHERO_API_KEY=your_payhero_api_key (For Mpesa STK Push, used by Edge Functions)
```

**Note**: `VITE_` prefixed variables are exposed to the client-side (Vite). Non-prefixed variables are typically for backend/server-side use.

### 4. Set Up Supabase Database

- Go to your Supabase project dashboard.
- Navigate to the SQL Editor.
- Create a new query.
- Copy the entire content of the `supabase/migrations/0000_init_schema.sql` file from this project.
- Paste it into the Supabase SQL Editor and run the query.

This will create all necessary tables, types, functions, RLS policies, and seed initial data.

Alternatively, if you have the Supabase CLI installed and configured for your project:

```bash
# Ensure your Supabase project is linked or URL is set in env for CLI
# cd /path/to/gvyeo-app
# supabase login (if not already logged in)
# supabase link --project-ref <your-project-id>

# Reset and apply the schema (BE CAREFUL: `db reset` will wipe existing data in the specified database)
# supabase db reset 
# supabase migration up (if migrations are managed via CLI and this is a new migration file)

# Or, directly apply the SQL script to your Supabase database using psql or Supabase SQL editor.
# Example using psql (replace with your actual Supabase connection string):
# psql "postgres://postgres:[YOUR-PASSWORD]@[YOUR-SUPABASE-HOST]:5432/postgres" < supabase/migrations/0000_init_schema.sql
```

**Important**: The `handle_new_user` trigger in the SQL schema is set up to populate the `public.users` table when a new user signs up via Supabase Auth. Ensure the `auth.users` table exists (which it will in a Supabase project) and that the trigger is created successfully.

### 5. Running the Development Server

To start the local development server:

```bash
pnpm run dev
```

The application will typically be available at `http://localhost:5173`.

### 6. Deploying to Vercel

1.  **Push your code to a Git repository** (e.g., GitHub, GitLab, Bitbucket).
2.  **Sign up or log in to Vercel.**
3.  **Import your Git repository** in Vercel.
4.  **Configure Project Settings:**
    *   Framework Preset: `Vite` (Vercel should auto-detect this).
    *   Build Command: `pnpm build` (or `vite build` if pnpm is not configured in Vercel build environment, though pnpm is preferred if `pnpm-lock.yaml` is present).
    *   Output Directory: `dist`.
    *   Install Command: `pnpm install`.
5.  **Add Environment Variables** in Vercel project settings:
    *   `VITE_SUPABASE_URL`: Your Supabase project URL.
    *   `VITE_SUPABASE_ANON_KEY`: Your Supabase project anon key.
    *   (If using Supabase Edge Functions deployed separately and called from client/Vercel serverless functions, ensure they are accessible and configured correctly).
6.  **Deploy.**

The `vercel.json` file in this project is configured to pass these environment variables during the build and to the runtime environment for client-side access.

## System Components & Features

(Refer to the detailed requirements document for a full list of features, including Authentication, Data Modeling, RPC & Business Logic, Frontend Pages, Security Policies, etc.)

Key technologies:

*   Frontend: React, Vite, Tailwind CSS, shadcn/ui (implicitly, as per `create_react_app` template)
*   Backend: Supabase (PostgreSQL, Auth, RLS, Stored Procedures, Edge Functions for PayHero integration)
*   Deployment: Vercel

