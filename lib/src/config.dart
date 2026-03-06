/// Supabase project URL and anon (publishable) key.
/// Use your project's anon key from Supabase Dashboard → Settings → API.
const String supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://ehteyunafhexqjwyjkpi.supabase.co',
);

const String supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'sb_publishable_DNNM4O7PamWSW8apvZHdhw_jmxOBvhz',
);
