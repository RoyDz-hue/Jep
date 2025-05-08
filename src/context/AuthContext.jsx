import React, { createContext, useState, useEffect, useContext } from 'react';
import { supabase } from '../lib/supabaseClient';

const AuthContext = createContext();

export const AuthProvider = ({ children }) => {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);
  const [userRole, setUserRole] = useState(null);

  useEffect(() => {
    const getSession = async () => {
      const { data: { session }, error } = await supabase.auth.getSession();
      if (error) {
        console.error('Error getting session:', error.message);
        setLoading(false);
        return;
      }
      setUser(session?.user ?? null);
      if (session?.user) {
        await fetchUserRole(session.user.id);
      }
      setLoading(false);
    };

    getSession();

    const { data: authListener } = supabase.auth.onAuthStateChange(async (_event, session) => {
      setUser(session?.user ?? null);
      if (session?.user) {
        await fetchUserRole(session.user.id);
      } else {
        setUserRole(null);
      }
      setLoading(false);
    });

    return () => {
      authListener?.subscription.unsubscribe();
    };
  }, []);

  const fetchUserRole = async (userId) => {
    try {
      // First, try to get role from user_metadata if it's set there directly by Supabase Auth
      const { data: { user: authUser }, error: authError } = await supabase.auth.admin.getUserById(userId); // Requires service_role key
      if (authError && authError.message !== "User not found") {
        // If we can't use admin API (e.g. from client-side without service key proxy)
        // or if there's another error, try fetching from public.users table.
        console.warn('Could not fetch user metadata directly, trying public.users table:', authError.message);
      } else if (authUser?.user_metadata?.role) {
        setUserRole(authUser.user_metadata.role);
        return;
      }
      
      // Fallback or primary method: Fetch role from public.users table
      const { data, error } = await supabase
        .from('users')
        .select('role')
        .eq('id', userId)
        .single();

      if (error) {
        console.error('Error fetching user role:', error.message);
        setUserRole(null);
        return;
      }
      setUserRole(data?.role || null);
    } catch (error) {
      console.error('Error in fetchUserRole:', error.message);
      setUserRole(null);
    }
  };

  const value = {
    signUp: (data) => supabase.auth.signUp(data),
    signIn: (data) => supabase.auth.signInWithPassword(data),
    signOut: () => supabase.auth.signOut(),
    user,
    userRole,
    loading,
  };

  return <AuthContext.Provider value={value}>{!loading && children}</AuthContext.Provider>;
};

export const useAuth = () => {
  return useContext(AuthContext);
};

