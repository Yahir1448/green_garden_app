/// Credenciales de conexión a tu proyecto de Supabase.
///
/// Reemplaza los valores de abajo con los de TU proyecto:
/// Supabase → Project Settings → API.
/// - `supabaseUrl` es el "Project URL".
/// - `supabaseAnonKey` es la "anon public key" (a veces llamada
///   también "publishable key" en proyectos nuevos).
///
/// Estas credenciales son seguras de incluir en la app: están
/// diseñadas para usarse desde el cliente. La seguridad real la dan
/// las políticas de Row Level Security definidas en `schema.sql`, no
/// el secreto de esta clave.
class SupabaseConfig {
  static const String supabaseUrl = 'https://njeifwrprkskdeaccjap.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5qZWlmd3Jwcmtza2RlYWNjamFwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk0MTMxNzEsImV4cCI6MjEwNDk4OTE3MX0.QIjyBBDnwAvAxLlgeCtzIfDX6Al0ryGbZ8fZL_f7pMs';
}