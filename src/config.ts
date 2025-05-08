// Directly setting the Supabase URL and Anon Key
// WARNING: This is generally not recommended for security reasons.
// These values will be embedded in your built application code.

const VITE_SUPABASE_URL = "https://pscopweerajcktddotty.supabase.co";
const VITE_SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBzY29wd2VlcmFqY2t0ZGRvdHR5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDY2ODgwMTYsImV4cCI6MjA2MjI2NDAxNn0.sbjjofiBaDdGF9-wIZ2ADpvnEOzSPAViFei8Fcv0hj0";

// No need for checks as they are hardcoded
// if (!VITE_SUPABASE_URL) {
//   throw new Error("VITE_SUPABASE_URL is not defined.");
// }
//
// if (!VITE_SUPABASE_ANON_KEY) {
//   throw new Error("VITE_SUPABASE_ANON_KEY is not defined.");
// }

export const supabaseUrl = VITE_SUPABASE_URL;
export const supabaseAnonKey = VITE_SUPABASE_ANON_KEY;

