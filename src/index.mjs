import { AuthController } from "./controller/AuthController.mjs";
import { ProtectedController } from "./controller/ProtectedController.mjs";

/**
 * Mappe tes routes API Gateway vers ces handlers :
 *  - GET  /auth/login     -> login
 *  - GET  /auth/callback  -> callback
 *  - POST /auth/refresh   -> refresh
 *  - GET  /auth/logout    -> logout
 *  - GET  /me             -> me
 *  - GET  /api/hello      -> hello
 */

export const login = async () => AuthController.login();
export const callback = async (event) => AuthController.callback(event);
export const refresh = async (event) => AuthController.refresh(event);
export const logout = async () => AuthController.logout();
export const me = async (event) => ProtectedController.me(event);
export const hello = async (event) => ProtectedController.hello(event);