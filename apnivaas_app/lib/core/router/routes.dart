/// The self sign-up routes (1.3.0), in their own file so a screen can name them without
/// importing the router (which imports every screen).
library;

/// "Who are you?" — Owner / Tenant / Staff. Public: reachable without a session.
const startRoute = '/start';

/// Create your account (Google; Facebook and Truecaller when configured). Public.
const createAccountRoute = '/create-account';
