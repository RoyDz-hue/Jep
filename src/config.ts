const VITE_SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
const VITE_SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!VITE_SUPABASE_URL) {
  throw new Error("VITE_SUPABASE_URL is not defined. Please check your .env file.");
}

if (!VITE_SUPABASE_ANON_KEY) {
  throw new Error("VITE_SUPABASE_ANON_KEY is not defined. Please check your .env file.");
}

export const supabaseUrl = VITE_SUPABASE_URL;
export const supabaseAnonKey = VITE_SUPABASE_ANON_KEY;

