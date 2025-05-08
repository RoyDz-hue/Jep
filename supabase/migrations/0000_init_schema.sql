-- GVYEO System Schema
-- This script creates all tables, types, functions, policies, and initial seed data.

-- Enable RLS for all tables by default
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM PUBLIC;

-- Create ENUM types
CREATE TYPE payment_category AS ENUM (
  'monthly',
  'fine',
  'goodwill',
  'support'
);

CREATE TYPE loan_status AS ENUM (
  'pending',
  'approved',
  'active',
  'paid',
  'defaulted',
  'rejected'
);

CREATE TYPE user_role AS ENUM (
  'member',
  'admin'
);

-- Create Tables
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid() REFERENCES auth.users(id) ON DELETE CASCADE,
  email VARCHAR(255) UNIQUE NOT NULL,
  name VARCHAR(255),
  phone VARCHAR(50),
  role user_role DEFAULT 'member' NOT NULL,
  referral_code VARCHAR(50) UNIQUE,
  referred_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
COMMENT ON TABLE users IS 'Stores user profile information, extending Supabase auth.users.';

CREATE TABLE loans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  principal NUMERIC(10, 2) NOT NULL CHECK (principal > 0),
  rate NUMERIC(5, 4) NOT NULL CHECK (rate >= 0 AND rate <= 1), -- Annual interest rate
  term_months INTEGER NOT NULL CHECK (term_months > 0),
  outstanding_balance NUMERIC(10, 2) NOT NULL CHECK (outstanding_balance >= 0),
  status loan_status DEFAULT 'pending' NOT NULL,
  issued_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
COMMENT ON TABLE loans IS 'Stores loan information for users.';

CREATE TABLE payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  loan_id UUID REFERENCES loans(id) ON DELETE SET NULL, -- A payment might not be tied to a specific loan (e.g. goodwill)
  amount NUMERIC(10, 2) NOT NULL CHECK (amount > 0),
  category payment_category NOT NULL,
  payment_timestamp TIMESTAMPTZ DEFAULT NOW(),
  tx_ref VARCHAR(255) UNIQUE, -- Transaction reference from payment gateway (e.g., Mpesa)
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
COMMENT ON TABLE payments IS 'Stores payment records for users.';

CREATE TABLE referrals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE, -- User who referred
  referee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE UNIQUE, -- User who was referred
  created_at TIMESTAMPTZ DEFAULT NOW()
);
COMMENT ON TABLE referrals IS 'Tracks referral relationships between users.';

CREATE TABLE app_settings (
    id SERIAL PRIMARY KEY,
    setting_key VARCHAR(255) UNIQUE NOT NULL,
    setting_value JSONB,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
COMMENT ON TABLE app_settings IS 'Stores central application settings like monthly fees, fine rules, etc.';

-- Functions to update `updated_at` timestamps
CREATE OR REPLACE FUNCTION trigger_set_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for `updated_at`
CREATE TRIGGER set_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION trigger_set_timestamp();

CREATE TRIGGER set_loans_updated_at
BEFORE UPDATE ON loans
FOR EACH ROW
EXECUTE FUNCTION trigger_set_timestamp();

CREATE TRIGGER set_payments_updated_at
BEFORE UPDATE ON payments
FOR EACH ROW
EXECUTE FUNCTION trigger_set_timestamp();

CREATE TRIGGER set_app_settings_updated_at
BEFORE UPDATE ON app_settings
FOR EACH ROW
EXECUTE FUNCTION trigger_set_timestamp();

-- Seed initial data (example)
INSERT INTO app_settings (setting_key, setting_value, description) VALUES
('monthly_fee', '{"amount": 100.00, "currency": "KES"}', 'Default monthly membership fee'),
('late_payment_fine_percentage', '{"percentage": 0.05}', 'Percentage fine for late loan payments (applied to overdue amount)'),
('referral_bonus_amount', '{"amount": 50.00, "currency": "KES"}', 'Bonus amount for successful referrals');

-- Supabase Auth Hook for new user
-- This function will be called by a trigger when a new user signs up.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  _referral_code TEXT;
  _referred_by_user_id UUID;
BEGIN
  -- Insert into public.users table
  INSERT INTO public.users (id, email, name, phone, role, referral_code)
  VALUES (
    NEW.id,
    NEW.email,
    NEW.raw_user_meta_data->>
'name', -- Assuming name is passed in metadata
    NEW.raw_user_meta_data->>
'phone', -- Assuming phone is passed in metadata
    COALESCE((NEW.raw_user_meta_data->>
'role')::user_role, 'member'), -- Default to 'member' if not provided
    substring(md5(random()::text || clock_timestamp()::text) from 1 for 8) -- Generate a unique referral code
  ) RETURNING users.id, users.referral_code INTO NEW.id, _referral_code;

  -- Handle referral if referral_code was provided during signup
  _referral_code := NEW.raw_user_meta_data->>
'referral_code';
  IF _referral_code IS NOT NULL THEN
    SELECT id INTO _referred_by_user_id FROM public.users WHERE referral_code = _referral_code;
    IF _referred_by_user_id IS NOT NULL THEN
      UPDATE public.users SET referred_by = _referred_by_user_id WHERE id = NEW.id;
      INSERT INTO public.referrals (referrer_id, referee_id) VALUES (_referred_by_user_id, NEW.id);
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for new user
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();


-- Row Level Security (RLS) Policies

-- USERS table
ALTER TABLE users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own profile." ON users
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile." ON users
  FOR UPDATE USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

CREATE POLICY "Admins can manage all user profiles." ON users
  FOR ALL USING (EXISTS (
    SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'
  ));

-- LOANS table
ALTER TABLE loans ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members can view their own loans." ON loans
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Members can create loans for themselves." ON loans
  FOR INSERT WITH CHECK (auth.uid() = user_id);
  -- Note: Further checks (e.g., admin approval) would be handled by application logic/RPC

CREATE POLICY "Admins can manage all loans." ON loans
  FOR ALL USING (EXISTS (
    SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'
  ));

-- PAYMENTS table
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Members can view their own payments." ON payments
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Members can create payments for themselves." ON payments
  FOR INSERT WITH CHECK (auth.uid() = user_id);
  -- Note: Payment creation might be restricted/triggered by RPCs (e.g., STK push callback)

CREATE POLICY "Admins can manage all payments." ON payments
  FOR ALL USING (EXISTS (
    SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'
  ));

-- REFERRALS table
ALTER TABLE referrals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own referral entries (as referrer or referee)." ON referrals
  FOR SELECT USING (auth.uid() = referrer_id OR auth.uid() = referee_id);

CREATE POLICY "Admins can manage all referrals." ON referrals
  FOR ALL USING (EXISTS (
    SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'
  ));
-- System should insert into referrals table via trusted functions (e.g. handle_new_user or RPC)

-- APP_SETTINGS table
ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins can manage application settings." ON app_settings
  FOR ALL USING (EXISTS (
    SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'
  ));

CREATE POLICY "Authenticated users can read application settings." ON app_settings
  FOR SELECT USING (auth.role() = 'authenticated');


-- Stored Procedures (RPC)

-- Example: Function to get user role (can be called via RPC)
CREATE OR REPLACE FUNCTION get_user_role(user_id_input UUID)
RETURNS user_role AS $$
DECLARE
  _role user_role;
BEGIN
  SELECT role INTO _role FROM public.users WHERE id = user_id_input;
  RETURN _role;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Further RPC functions for business logic (Mpesa STK Push, record payment, calculate dues, etc.)
-- will be added here. These will often be SECURITY DEFINER functions to allow specific
-- operations that users might not have direct RLS permission for.


-- Example: Issue Mpesa STK Push (placeholder - requires Edge Function for HTTP call)
-- This SQL function would be called by the frontend, and it would then invoke an Edge Function.
CREATE OR REPLACE FUNCTION issue_stk_push(user_id_input UUID, loan_id_input UUID, amount_input NUMERIC)
RETURNS JSONB AS $$
DECLARE
  -- Variables for PayHero API call
  payhero_api_key TEXT;         -- Fetched from a secure place or env var via Edge Function
  payhero_endpoint TEXT := 'https://api.payhero.co.ke/stk_push'; -- Example endpoint
  phone_number TEXT;
  response JSONB;
BEGIN
  -- Get user's phone number
  SELECT phone INTO phone_number FROM users WHERE id = user_id_input;
  IF phone_number IS NULL THEN
    RETURN jsonb_build_object('error', 'User phone number not found.');
  END IF;

  -- In a real scenario, this function would trigger an Edge Function
  -- to make the HTTP POST request to PayHero, as Postgres cannot directly make outbound HTTP requests easily.
  -- The Edge Function would handle the API key securely.

  -- For now, this is a placeholder response.
  -- The Edge Function would return a more meaningful response from PayHero.
  response := jsonb_build_object(
    'status', 'pending_stk_push_trigger',
    'message', 'STK Push to ' || phone_number || ' for amount ' || amount_input || ' for loan ' || loan_id_input || ' is being initiated via Edge Function.',
    'transaction_id', 'temp_tx_' || gen_random_uuid()::text -- Placeholder transaction ID
  );

  -- Optionally, log the attempt or create a pending payment record here

  RETURN response;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER; -- SECURITY DEFINER if it needs to access user phone or other restricted data


-- Function to record a payment (e.g., called by PayHero callback via an Edge Function)
CREATE OR REPLACE FUNCTION record_payment(
  p_user_id UUID,
  p_loan_id UUID,
  p_amount NUMERIC,
  p_category payment_category,
  p_tx_ref VARCHAR(255),
  p_notes TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
  new_payment_id UUID;
  current_outstanding_balance NUMERIC;
  new_outstanding_balance NUMERIC;
BEGIN
  -- Insert the payment
  INSERT INTO payments (user_id, loan_id, amount, category, tx_ref, notes)
  VALUES (p_user_id, p_loan_id, p_amount, p_category, p_tx_ref, p_notes)
  RETURNING id INTO new_payment_id;

  -- If it's a loan payment, update the loan balance
  IF p_loan_id IS NOT NULL AND (p_category = 'monthly' OR p_category = 'fine') THEN
    SELECT outstanding_balance INTO current_outstanding_balance FROM loans WHERE id = p_loan_id AND user_id = p_user_id;
    
    IF FOUND THEN
      new_outstanding_balance := current_outstanding_balance - p_amount;
      IF new_outstanding_balance < 0 THEN
        new_outstanding_balance := 0;
      END IF;

      UPDATE loans
      SET outstanding_balance = new_outstanding_balance,
          status = CASE 
                     WHEN new_outstanding_balance <= 0 THEN 'paid'::loan_status
                     ELSE status 
                   END
      WHERE id = p_loan_id;
    END IF;
  END IF;

  RETURN new_payment_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Placeholder for other RPCs (calculate monthly dues, assess fines, aggregate history, referral bonuses)
-- These would be implemented based on specific business rules.


-- Grant USAGE on schema public to supabase_auth_admin and anon, authenticated roles
GRANT USAGE ON SCHEMA public TO supabase_auth_admin, anon, authenticated;

-- Grant EXECUTE on all functions in schema public to authenticated role
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO service_role; -- Allow service role to execute all functions

-- Grant SELECT, INSERT, UPDATE, DELETE on all tables in schema public to service_role
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO service_role;

-- Grant permissions for anon and authenticated roles as per RLS policies
-- (RLS policies will handle actual access control for these roles)
GRANT SELECT, INSERT, UPDATE, DELETE ON users TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON loans TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON payments TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON referrals TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON app_settings TO anon, authenticated;


-- Make sure the `handle_new_user` function is owned by supabase_admin or a superuser
-- and that the trigger is also created by a user with sufficient privileges.
-- This is typically handled correctly when running migrations via Supabase CLI or dashboard.


-- Final check: Ensure auth.users table exists before creating foreign key references.
-- This script assumes it's run in an environment where Supabase Auth is already set up.


-- TODO: Add more specific RPC functions as per requirements:
-- Calculate monthly dues automatically based on central settings.
-- Assess fines for late or missed payments.
-- Aggregate a member’s payment history and outstanding balance.
-- Produce referral bonuses or statistics.






-- Additional RPC Functions for Business Logic

-- Function to calculate current due amount for a loan (simplified example)
-- This would typically involve complex logic based on amortization schedules, payment history, etc.
CREATE OR REPLACE FUNCTION calculate_loan_due_amount(p_loan_id UUID)
RETURNS NUMERIC AS $$
DECLARE
  due_amount NUMERIC := 0;
  loan_principal NUMERIC;
  loan_rate NUMERIC;
  loan_term INTEGER; -- in months
  monthly_payment NUMERIC;
  -- Add more variables for grace periods, last payment date, etc.
BEGIN
  SELECT principal, rate, term_months INTO loan_principal, loan_rate, loan_term
  FROM loans WHERE id = p_loan_id;

  IF NOT FOUND THEN
    RETURN 0; -- Or raise an exception
  END IF;

  -- Simplified monthly payment calculation (e.g., PITI is more complex)
  -- M = P [ i(1 + i)^n ] / [ (1 + i)^n – 1]
  -- where P = principal, i = monthly interest rate, n = number of months
  IF loan_rate > 0 THEN
    DECLARE
      monthly_interest_rate NUMERIC := loan_rate / 12;
    BEGIN
      monthly_payment := loan_principal * (monthly_interest_rate * (1 + monthly_interest_rate)^loan_term) / ((1 + monthly_interest_rate)^loan_term - 1);
    END;
  ELSE
    monthly_payment := loan_principal / loan_term;
  END IF;

  -- This is highly simplified. Real due calculation needs to check payment history, due dates.
  -- For this example, let's assume the monthly payment is the due amount if the loan is active.
  SELECT CASE status WHEN 'active' THEN monthly_payment ELSE 0 END INTO due_amount
  FROM loans WHERE id = p_loan_id;
  
  RETURN COALESCE(due_amount, 0);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Function to assess a fine for a loan (placeholder)
CREATE OR REPLACE FUNCTION assess_fine_for_loan(p_loan_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  fine_percentage NUMERIC;
  due_amount NUMERIC;
  outstanding NUMERIC;
  loan_status_val loan_status;
  user_id_val UUID;
BEGIN
  -- Get fine percentage from app_settings
  SELECT (setting_value->>
'percentage')::NUMERIC INTO fine_percentage 
  FROM app_settings WHERE setting_key = 'late_payment_fine_percentage';

  IF fine_percentage IS NULL OR fine_percentage <= 0 THEN
    RETURN FALSE; -- No fine configured or invalid configuration
  END IF;

  SELECT outstanding_balance, status, user_id INTO outstanding, loan_status_val, user_id_val FROM loans WHERE id = p_loan_id;

  -- Placeholder: Logic to determine if a payment is late and fine is applicable
  -- This would involve checking due dates, grace periods, payment history.
  -- For now, let's assume if a loan is 'active' and has an outstanding balance, a fine *could* be applied.
  -- This is NOT a complete implementation.
  IF loan_status_val = 'active' AND outstanding > 0 THEN
    -- Calculate fine amount (e.g., percentage of outstanding or due amount)
    DECLARE
      fine_amount NUMERIC := outstanding * fine_percentage;
    BEGIN
      -- Record the fine as a payment of category 'fine'
      -- This might also increase the outstanding_balance or be a separate charge.
      -- For simplicity, let's assume it's recorded as a new 'fine' payment due.
      -- A more robust system might add this to a fines_due table or update loan terms.
      PERFORM record_payment(user_id_val, p_loan_id, fine_amount, 'fine'::payment_category, 'fine_assessment_' || p_loan_id::text || '_' || NOW()::text);
      RETURN TRUE;
    EXCEPTION WHEN OTHERS THEN
        -- Log error or handle
        RETURN FALSE;
    END;
  END IF;

  RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Function to get a user's payment summary
CREATE OR REPLACE FUNCTION get_user_payment_summary(p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
  total_paid NUMERIC;
  total_loans_principal NUMERIC;
  total_outstanding_balance NUMERIC;
  active_loans_count INTEGER;
BEGIN
  SELECT COALESCE(SUM(amount), 0) INTO total_paid FROM payments WHERE user_id = p_user_id AND category != 'fine'; -- Exclude fines from 'paid' for this summary if desired
  SELECT COALESCE(SUM(principal), 0) INTO total_loans_principal FROM loans WHERE user_id = p_user_id AND status IN ('approved', 'active', 'paid', 'defaulted');
  SELECT COALESCE(SUM(outstanding_balance), 0) INTO total_outstanding_balance FROM loans WHERE user_id = p_user_id AND status = 'active';
  SELECT COUNT(*) INTO active_loans_count FROM loans WHERE user_id = p_user_id AND status = 'active';

  RETURN jsonb_build_object(
    'user_id', p_user_id,
    'total_paid_towards_loans_and_dues', total_paid,
    'total_principal_on_loans_taken', total_loans_principal,
    'current_total_outstanding_loan_balance', total_outstanding_balance,
    'active_loans_count', active_loans_count
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Function to process a referral bonus (placeholder)
CREATE OR REPLACE FUNCTION process_referral_bonus(p_referrer_id UUID, p_referee_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  bonus_amount NUMERIC;
  bonus_currency TEXT;
BEGIN
  -- Get referral bonus amount from app_settings
  SELECT (setting_value->>
'amount')::NUMERIC, (setting_value->>
'currency')::TEXT 
  INTO bonus_amount, bonus_currency
  FROM app_settings WHERE setting_key = 'referral_bonus_amount';

  IF bonus_amount IS NULL OR bonus_amount <= 0 THEN
    RETURN FALSE; -- No bonus configured or invalid amount
  END IF;

  -- Check if referral exists and is valid (e.g., referee is active, first-time referral)
  IF NOT EXISTS (SELECT 1 FROM referrals WHERE referrer_id = p_referrer_id AND referee_id = p_referee_id) THEN
    RETURN FALSE; -- Referral not found
  END IF;

  -- Placeholder: Logic to credit the referrer
  -- This could be creating a 'goodwill' payment or a credit to their account.
  -- For simplicity, let's assume we record a 'support' (bonus) payment for the referrer.
  PERFORM record_payment(p_referrer_id, NULL, bonus_amount, 'support'::payment_category, 'referral_bonus_' || p_referee_id::text);
  
  -- Optionally, mark the referral as bonus_paid in the referrals table if you add such a column.
  
  RETURN TRUE;
EXCEPTION WHEN OTHERS THEN
    -- Log error
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION calculate_loan_due_amount(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION assess_fine_for_loan(UUID) TO authenticated; -- Or service_role if only backend initiated
GRANT EXECUTE ON FUNCTION get_user_payment_summary(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION process_referral_bonus(UUID, UUID) TO authenticated; -- Or service_role

