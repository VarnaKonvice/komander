import { GoogleAuth } from 'google-auth-library';
import { CALENDAR_NAMES, MANAGED_BY } from './calendar-reconciliation.mjs';

const CALENDAR_SCOPE = 'https://www.googleapis.com/auth/calendar';
const API_ROOT = 'https://www.googleapis.com/calendar/v3';

function requiredEnvironment(env, name) {
  const value = typeof env[name] === 'string' ? env[name].trim() : '';
  if (!value) throw new Error(`Missing required calendar sync configuration: ${name}.`);
  return value;
}

export function readWriteConfiguration(env = process.env) {
  const credentialText = requiredEnvironment(env, 'LC_GOOGLE_SERVICE_ACCOUNT_JSON');
  const procedures = requiredEnvironment(env, 'LC_GOOGLE_CALENDAR_PROCEDURES_ID');
  const meals = requiredEnvironment(env, 'LC_GOOGLE_CALENDAR_MEALS_ID');
  let credentials;
  try {
    credentials = JSON.parse(credentialText);
  } catch {
    throw new Error('LC_GOOGLE_SERVICE_ACCOUNT_JSON is not valid JSON.');
  }
  if (credentials.type !== 'service_account' || typeof credentials.client_email !== 'string' || !credentials.client_email.trim() || typeof credentials.private_key !== 'string' || !credentials.private_key.trim()) {
    throw new Error('LC_GOOGLE_SERVICE_ACCOUNT_JSON is not a valid service account credential.');
  }
  return {
    credentials,
    calendarIds: { Procedury: procedures, 'Jídlo': meals }
  };
}

export class GoogleCalendarAdapter {
  constructor(authClient, calendarIds) {
    this.authClient = authClient;
    this.calendarIds = calendarIds;
  }

  calendarId(calendarName) {
    if (!CALENDAR_NAMES.includes(calendarName) || !this.calendarIds[calendarName]) throw new Error(`Unknown Google Calendar target: ${calendarName}.`);
    return this.calendarIds[calendarName];
  }

  async request(method, url, data) {
    try {
      const response = await this.authClient.request({ method, url, data });
      return response.data;
    } catch (error) {
      const status = error && error.response && error.response.status;
      throw new Error(`Google Calendar API ${method} request failed${status ? ` with status ${status}` : ''}.`);
    }
  }

  async listEvents(calendarName) {
    const items = [];
    let pageToken = null;
    do {
      const url = new URL(`${API_ROOT}/calendars/${encodeURIComponent(this.calendarId(calendarName))}/events`);
      url.searchParams.set('privateExtendedProperty', `managedBy=${MANAGED_BY}`);
      url.searchParams.set('showDeleted', 'false');
      url.searchParams.set('maxResults', '2500');
      if (pageToken) url.searchParams.set('pageToken', pageToken);
      const data = await this.request('GET', url.href);
      items.push(...(Array.isArray(data && data.items) ? data.items : []));
      pageToken = data && data.nextPageToken || null;
    } while (pageToken);
    return items;
  }

  async createEvent(calendarName, resource) {
    const url = new URL(`${API_ROOT}/calendars/${encodeURIComponent(this.calendarId(calendarName))}/events`);
    url.searchParams.set('sendUpdates', 'none');
    return this.request('POST', url.href, resource);
  }

  async updateEvent(calendarName, eventId, resource) {
    const url = new URL(`${API_ROOT}/calendars/${encodeURIComponent(this.calendarId(calendarName))}/events/${encodeURIComponent(eventId)}`);
    url.searchParams.set('sendUpdates', 'none');
    return this.request('PUT', url.href, resource);
  }

  async deleteEvent(calendarName, eventId) {
    const url = new URL(`${API_ROOT}/calendars/${encodeURIComponent(this.calendarId(calendarName))}/events/${encodeURIComponent(eventId)}`);
    url.searchParams.set('sendUpdates', 'none');
    await this.request('DELETE', url.href);
  }
}

export async function createGoogleCalendarAdapter(configuration) {
  try {
    const auth = new GoogleAuth({ credentials: configuration.credentials, scopes: [CALENDAR_SCOPE] });
    const authClient = await auth.getClient();
    return new GoogleCalendarAdapter(authClient, configuration.calendarIds);
  } catch {
    throw new Error('Google service account authentication failed.');
  }
}
