const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

function extractCoordinates(value: string) {
  const text = decodeURIComponent(value);
  const patterns = [
    /@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/,
    /!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)/,
    /(?:[?&](?:q|query|ll)=|\/search\/)(-?\d+(?:\.\d+)?)[,;\s]+(-?\d+(?:\.\d+)?)/i,
    /(-?\d{1,2}(?:\.\d+)?)\s*[,;]\s*(-?\d{1,3}(?:\.\d+)?)/,
  ];
  for (const pattern of patterns) {
    const match = text.match(pattern);
    if (!match) continue;
    const latitude = Number(match[1]);
    const longitude = Number(match[2]);
    if (
      Number.isFinite(latitude) &&
      Number.isFinite(longitude) &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180
    ) {
      return { latitude, longitude };
    }
  }
  return null;
}

// Supabase menyediakan Deno secara global saat Edge Function dijalankan.
// @ts-ignore Deno tersedia di Supabase Edge Runtime.
Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  try {
    const body = await request.json();
    const input = typeof body.url === 'string' ? body.url.trim() : '';
    if (!input) return json({ error: 'URL Google Maps wajib diisi.' }, 400);

    let url: URL;
    try {
      url = new URL(input);
    } catch (_) {
      return json({ error: 'URL Google Maps tidak valid.' }, 400);
    }

    const response = await fetch(url, { redirect: 'follow' });
    const resolvedUrl = response.url;
    const html = await response.text();
    const coordinates = extractCoordinates(`${resolvedUrl}\n${html}`);
    if (!coordinates) {
      return json({ error: 'Koordinat tidak ditemukan pada tautan Google Maps.' }, 422);
    }
    return json({ ...coordinates, resolvedUrl });
  } catch (_) {
    return json({ error: 'Tautan Google Maps tidak dapat diproses.' }, 500);
  }
});
