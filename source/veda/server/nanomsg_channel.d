module veda.server.nanomsg_channel;

import core.thread, std.stdio, std.format, std.datetime, std.concurrency, std.conv, std.outbuffer, std.string, std.uuid, std.path, std.json;
import veda.core.common.context, veda.core.util.utils, veda.util.tools, veda.onto.onto, veda.core.impl.thread_context;
import kaleidic.nanomsg.nano;

// ////// Logger ///////////////////////////////////////////
import veda.common.logger;
Logger _log;
Logger log()
{
    if (_log is null)
        _log = new Logger("veda-core-server", "log", "N-CHANNEL");
    return _log;
}
// ////// ////// ///////////////////////////////////////////

void nanomsg_channel(string thread_name)
{
    int    sock;
    string url = "tcp://127.0.0.1:9112\0";

    try
    {
        Context                      context;

        core.thread.Thread.getThis().name = thread_name;

        sock = nn_socket(AF_SP, NN_REP);
        if (sock < 0)
        {
            log.trace("ERR! cannot create socket");
            return;
        }
        if (nn_bind(sock, cast(char *)url) < 0)
        {
            log.trace("ERR! cannot bind to socket, url=%s", url);
            return;
        }
        log.trace("success bind to %s", url);

        if (context is null)
            context = new PThreadContext("cfg:standart_node", thread_name, P_MODULE.n_channel, log, null);

        // SEND ready
        receive((Tid tid_response_reciever)
                {
                    send(tid_response_reciever, true);
                });

        while (true)
        {
            try
            {
                char *buf  = cast(char *)0;
                int  bytes = nn_recv(sock, &buf, NN_MSG, 0);
                if (bytes >= 0)
                {
                    string req = to!string(buf);
//                    log.trace("RECEIVED (%s)", req);

                    string rep = context.execute(req);

                    nn_freemsg(buf);

                    bytes = nn_send(sock, cast(char *)rep, rep.length + 1, 0);
//                    log.trace("SENDING (%s) %d bytes", rep, bytes);
                }
            }
            catch (Throwable tr)
            {
                log.trace("ERR! MAIN LOOP", tr.info);
            }
        }
    }
    finally
    {
        writeln("exit form thread ", thread_name);
    }
}
