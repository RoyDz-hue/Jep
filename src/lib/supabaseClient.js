import { createClient } from '@supabase/supabase-js';
import { supabaseUrl, supabaseAnonKey } from '../config'; // Updated import

// The checks for undefined are now in config.ts, so they are not strictly needed here again
// but it doesn't hurt to keep them as a safeguard if this module were used independently.
if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error('Supabase URL and Anon Key must be defined and exported from config.ts');
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey);

