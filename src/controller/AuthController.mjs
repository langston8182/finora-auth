import { AuthService } from "../service/AuthService.mjs";
import { redirect, json } from "../utils/http.mjs";

export class AuthController {
    static async login() {
        const { authorizeUrl, tmpCookie } = AuthService.buildAuthorizeRedirect();
        return redirect(authorizeUrl, [tmpCookie]);
    }

    /** @param {any} event */
    static async callback(event) {
        const result = await AuthService.exchangeCodeForTokens(event);
        if (result.error) {
            return json(result.status, { error: result.error, details: result.details });
        }
        return redirect(result.redirectTo, result.cookiesOut);
    }

    /** @param {any} event */
    static async refresh(event) {
        const result = await AuthService.refresh(event);
        if (result.error) {
            return json(result.status, { error: result.error, details: result.details });
        }
        return json(200, { ok: true }, result.cookiesOut);
    }

    static async logout() {
        const { logoutUrl, cookies } = AuthService.buildLogoutRedirect();
        return redirect(logoutUrl, cookies);
    }
}