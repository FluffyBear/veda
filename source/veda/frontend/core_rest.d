module veda.frontend.core_rest;

import std.stdio, std.datetime, std.conv, std.string, std.datetime, std.file, core.runtime, core.thread, core.sys.posix.signal, std.uuid, std.utf;
import core.vararg, core.stdc.stdarg, core.atomic, std.uri;
import vibe.d, vibe.core.core, vibe.core.log, vibe.core.task, vibe.inet.mimetypes;
import properd, TrailDB;
import veda.common.type, veda.core.common.context, veda.core.common.know_predicates, veda.core.common.define, veda.core.common.log_msg;
import veda.onto.onto, veda.onto.individual, veda.onto.resource, veda.onto.lang, veda.frontend.individual8vjson;
import veda.frontend.cbor8vjson, veda.util.queue;

// ////// Logger ///////////////////////////////////////////
import veda.common.logger;
veda.common.logger.Logger _log;
veda.common.logger.Logger log()
{
    if (_log is null)
        _log = new veda.common.logger.Logger("veda-core-webserver-" ~ text(http_port), "log", "REST");
    return _log;
}
// ////// ////// ///////////////////////////////////////////

public short        http_port         = 8080;
public bool         is_external_users = false;

public const string veda_schema__File          = "v-s:File";
public const string veda_schema__fileName      = "v-s:fileName";
public const string veda_schema__fileSize      = "v-s:fileSize";
public const string veda_schema__fileThumbnail = "v-s:fileThumbnail";

static this() {
    Lang =
    [
        "NONE":LANG.NONE, "none":LANG.NONE,
        "RU":LANG.RU, "ru":LANG.RU,
        "EN":LANG.EN, "en":LANG.EN
    ];

    Resource_type =
    [
        "Uri":DataType.Uri,
        "String":DataType.String,
        "Integer":DataType.Integer,
        "Datetime":DataType.Datetime,
        "Decimal":DataType.Decimal,
        "Boolean":DataType.Boolean,
    ];

    try
    {
        mkdir(attachments_db_path);
    }
    catch (Exception ex)
    {
    }
}

//////////////////////////////////////////////////// Rest API /////////////////////////////////////////////////////////////////

interface VedaStorageRest_API {
    /**
     * получить для индивида список прав на ресурс.
     * Params: ticket = указывает на индивида
     *	       uri    = uri ресурса
     * Returns: JSON
     */
    @path("get_rights") @method(HTTPMethod.GET)
    Json get_rights(string ticket, string uri);

    /**
     * получить для индивида детализированный список прав на ресурс.
     * Params: ticket = указывает на индивида
     *	       uri    = uri ресурса
     * Returns: JSON
     */
    @path("get_rights_origin") @method(HTTPMethod.GET)
    Json[] get_rights_origin(string ticket, string uri);

    @path("get_membership") @method(HTTPMethod.GET)
    Json get_membership(string ticket, string uri);

    @path("authenticate") @method(HTTPMethod.GET)
    Ticket authenticate(string login, string password);

    @path("get_ticket_trusted") @method(HTTPMethod.GET)
    Ticket get_ticket_trusted(string ticket, string login);

    @path("is_ticket_valid") @method(HTTPMethod.GET)
    bool is_ticket_valid(string ticket);

    @path("get_operation_state") @method(HTTPMethod.GET)
    long get_operation_state(int module_id, long wait_op_id);

    @path("send_to_module") @method(HTTPMethod.GET)
    void send_to_module(int module_id, string msg);

    @path("flush") @method(HTTPMethod.GET)
    void flush(int module_id, long wait_op_id);

    @path("set_trace") @method(HTTPMethod.GET)
    void set_trace(int idx, bool state);

    @path("backup") @method(HTTPMethod.GET)
    void backup(bool to_binlog);

    @path("count_individuals") @method(HTTPMethod.GET)
    long count_individuals();

    @path("query") @method(HTTPMethod.GET)
    SearchResult query(string ticket, string query, string sort = null, string databases = null, bool reopen = false, int from = 0, int top = 10000,
                       int limit = 10000, bool trace = false);

    @path("get_individuals") @method(HTTPMethod.POST)
    Json[] get_individuals(string ticket, string[] uris);

    @path("get_individual") @method(HTTPMethod.GET)
    Json get_individual(string ticket, string uri, bool reopen = false);

    @path("put_individual") @method(HTTPMethod.PUT)
    OpResult put_individual(string ticket, Json individual, long assigned_subsystems, string event_id);

    @path("put_individuals") @method(HTTPMethod.PUT)
    OpResult[] put_individuals(string ticket, Json[] individual, long assigned_subsystems, string event_id);

    @path("remove_individual") @method(HTTPMethod.PUT)
    OpResult remove_individual(string ticket, string uri, long assigned_subsystems, string event_id);

    @path("remove_from_individual") @method(HTTPMethod.PUT)
    OpResult remove_from_individual(string ticket, Json individual, long assigned_subsystems, string event_id);

    @path("set_in_individual") @method(HTTPMethod.PUT)
    OpResult set_in_individual(string ticket, Json individual, long assigned_subsystems, string event_id);

    @path("add_to_individual") @method(HTTPMethod.PUT)
    OpResult add_to_individual(string ticket, Json individual, long assigned_subsystems, string event_id);
}

extern (C) void handleTerminationR(int _signal)
{
//    log.trace("!SYS: veda.app: caught signal: %s", text(_signal));

    if (tdb_cons !is null)
    {
        log.trace("flush trail db");
        tdb_cons.finalize();
    }

    writefln("!SYS: veda.app.rest: caught signal: %s", text(_signal));

    vibe.core.core.exitEventLoop();

    writeln("!SYS: veda.app: exit");

    thread_term();
    Runtime.terminate();

//    kill(getpid(), SIGKILL);
//    exit(_signal);
}


class VedaStorageRest : VedaStorageRest_API
{
    private Context context;
//    string[ string ] properties;
    int             last_used_tid = 0;
    void function(int sig) shutdown;

    this(Context _local_context, void function(int sig) _shutdown)
    {
        bsd_signal(SIGINT, &handleTerminationR);
        shutdown = _shutdown;
        context  = _local_context;
    }

/////////////////////////////////////////////////////////////////////////////////////////////////////////////

    void fileManager(HTTPServerRequest req, HTTPServerResponse res)
    {
        //log.trace ("fileManager: req=%s", req);

        string uri;
        // uri субьекта

        long pos = lastIndexOf(req.path, "/");

        if (pos > 0)
        {
            uri = req.path[ pos + 1..$ ];
        }
        else
            return;

        // найдем в хранилище указанного субьекта

        //log.trace("@v uri=%s", uri);
        auto   ticket_ff = "ticket" in req.query;
        string _ticket;

        if (ticket_ff !is null)
            _ticket = cast(string)*ticket_ff;
        else
            _ticket = req.cookies.get("ticket", "");

        //log.trace("@v ticket=%s", _ticket);

        if (uri.length > 3 && _ticket !is null)
        {
            Ticket     *ticket = get_ticket(context, _ticket);

            Individual file_info;

            ResultCode rc = ticket.result;
            if (rc == ResultCode.OK)
            {
                file_info = context.get_individual(ticket, uri);

                //log.trace("@v file_info=%s", file_info);
                auto fileServerSettings = new HTTPFileServerSettings;
                fileServerSettings.encodingFileExtension = [ "jpeg":".JPG" ];

                string path     = file_info.getFirstResource("v-s:filePath").get!string;
                string file_uri = file_info.getFirstResource("v-s:fileUri").get!string;

                if (path !is null && file_uri !is null && file_uri.length > 0)
                {
                    if (path.length > 0)
                        path = path ~ "/";

                    string full_path = attachments_db_path ~ "/" ~ path ~ file_uri;

                    enforce(exists(full_path), "No file found!");

                    HTTPServerRequestDelegate dg =
                        serveStaticFile(full_path, fileServerSettings);

                    string originFileName = file_info.getFirstResource(veda_schema__fileName).get!string;

                    //log.trace("@v originFileName=%s", originFileName);
                    //log.trace("@v getMimeTypeForFile(originFileName)=%s", getMimeTypeForFile(originFileName));

                    string encoded_originFileName = encode(originFileName);

                    encoded_originFileName = encoded_originFileName.replace(",", " ");

                    string ss = "attachment; filename*=UTF-8''" ~ encoded_originFileName;

                    res.headers[ "Content-Disposition" ] = ss;

                    //log.trace ("fileManager: res.headers=%s", res.headers);

                    res.contentType = getMimeTypeForFile(originFileName);
                    dg(req, res);
                }
                else
                {
                    log.trace("ERR! get_file:incomplete individual of v-s:File, It does not contain predicate v-s:filePath or v-s:fileUri: %s",
                              file_info);
                }
            }
        }
    }

    override :

    Json get_rights(string _ticket, string uri)
    {
        ResultCode rc;
        ubyte      right_res;
        Json       res;
        Ticket     *ticket;

        try
        {
            ticket = get_ticket(context, _ticket);

            if (ticket.result != ResultCode.OK)
                throw new HTTPStatusException(ticket.result);

            right_res = context.get_rights(ticket, uri);

            Individual indv_res;
            indv_res.uri = "_";

            indv_res.addResource(rdf__type, Resource(DataType.Uri, veda_schema__PermissionStatement));

            if ((right_res & Access.can_read) > 0)
                indv_res.addResource("v-s:canRead", Resource(true));

            if ((right_res & Access.can_update) > 0)
                indv_res.addResource("v-s:canUpdate", Resource(true));

            if ((right_res & Access.can_delete) > 0)
                indv_res.addResource("v-s:canDelete", Resource(true));

            if ((right_res & Access.can_create) > 0)
                indv_res.addResource("v-s:canCreate", Resource(true));

            res = individual_to_json(indv_res);
            return res;
        }
        finally
        {
        }
    }

    Json get_membership(string _ticket, string uri)
    {
        Json       json;

        Ticket     *ticket;
        ResultCode rc;

        try
        {
            ticket = get_ticket(context, _ticket);
            if (ticket.result != ResultCode.OK)
                throw new HTTPStatusException(ticket.result);

            Individual indv_res = Individual.init;
            indv_res.uri = "_";
            indv_res.addResource(rdf__type,
                                 Resource(DataType.Uri, "v-s:Membership"));
            indv_res.addResource("v-s:resource",
                                 Resource(DataType.Uri, uri));

            void trace_group(string resource_group)
            {
                indv_res.addResource("v-s:memberOf",
                                     Resource(DataType.Uri, resource_group));
            }

            context.get_membership_from_acl(ticket, uri, &trace_group);

            json = individual_to_json(indv_res);
            return json;
        }
        finally
        {
        }
    }

    Json[] get_rights_origin(string _ticket, string uri)
    {
        Json[]     json;

        Ticket     *ticket;
        ResultCode rc;

        try
        {
            Individual[] res;

            ticket = get_ticket(context, _ticket);
            if (ticket.result != ResultCode.OK)
                throw new HTTPStatusException(ticket.result);

            string     all_info;

            Individual indv_info = Individual.init;

            indv_info.uri = "_";
            indv_info.addResource(rdf__type,
                                  Resource(DataType.Uri, veda_schema__PermissionStatement));
            indv_info.addResource(veda_schema__permissionObject,
                                  Resource(DataType.Uri, "?"));
            indv_info.addResource(veda_schema__permissionSubject,
                                  Resource(DataType.Uri, "?"));


            void trace_info(string info)
            {
                all_info ~= info ~ "\n";
            }

            void trace_acl(string resource_group, string subject_group, string right)
            {
                Individual indv_res = Individual.init;

                indv_res.uri = "_";
                indv_res.addResource(rdf__type,
                                     Resource(DataType.Uri, veda_schema__PermissionStatement));
                indv_res.addResource(veda_schema__permissionObject,
                                     Resource(DataType.Uri, resource_group));
                indv_res.addResource(veda_schema__permissionSubject,
                                     Resource(DataType.Uri, subject_group));
                indv_res.addResource(right, Resource(true));

                res ~= indv_res;
            }

            context.get_rights_origin_from_acl(ticket, uri, &trace_acl, &trace_info);

            indv_info.addResource("rdfs:comment", Resource(all_info));
            res ~= indv_info;

            json = Json[].init;
            foreach (individual; res)
                json ~= individual_to_json(individual);

            return json;
        }
        finally
        {
        }
    }

    Ticket authenticate(string login, string password)
    {
        Ticket ticket;

        try
        {
            if (wsc_server_task !is Task.init)
            {
                Json json = Json.emptyObject;
                json[ "function" ] = "authenticate";
                json[ "login" ]    = login;
                json[ "password" ] = password;

                vibe.core.concurrency.send(wsc_server_task, json, Task.getThis());

                string resp;
                vibe.core.concurrency.receive((string res){ resp = res; });

                if (resp is null)
                    throw new HTTPStatusException(ResultCode.Not_Authorized);

                Json jres = parseJson(resp);
                //log.trace("jres '%s'", jres);

                string type_msg = jres[ "type" ].get!string;

                //log.trace("type_msg '%s'", type_msg);

                if (type_msg != "ticket")
                    throw new HTTPStatusException(ResultCode.Not_Authorized);

                ticket.user_uri = jres[ "user_uri" ].get!string;

                ticket.end_time = jres[ "end_time" ].get!long;
                ticket.id       = jres[ "id" ].get!string;
                ticket.result   = cast(ResultCode)jres[ "result" ].get!long;

                if (is_external_users)
                {
                    log.trace("authenticate:check external user (%s)", ticket.user_uri);
                    Individual user = context.get_individual(&ticket, ticket.user_uri);
                    if (user.exists("v-s:origin", Resource("External User")) == false)
                    {
                        log.trace("ERR! authenticate:user (%s) is not external", ticket.user_uri);
                        ticket = Ticket.init;
                        throw new HTTPStatusException(ResultCode.Not_Authorized);
                    }
                    external_users_ticket_id[ ticket.user_uri ] = true;
                }

                //log.trace("new ticket= '%s'", ticket);
            }

//        Ticket ticket = context.authenticate(login, password, &create_new_ticket);

            if (ticket.result != ResultCode.OK)
                throw new HTTPStatusException(ticket.result);

            return ticket;
        }
        finally
        {
        }
    }

    Ticket get_ticket_trusted(string ticket_id, string login)
    {
        Ticket ticket;

        try
        {
            if (wsc_server_task !is Task.init)
            {
                Json json = Json.emptyObject;
                json[ "function" ] = "get_ticket_trusted";
                json[ "ticket" ]   = ticket_id;
                json[ "login" ]    = login;

                vibe.core.concurrency.send(wsc_server_task, json, Task.getThis());

                string resp;
                vibe.core.concurrency.receive((string res){ resp = res; });

                if (resp is null)
                    throw new HTTPStatusException(ResultCode.Not_Authorized);

                Json jres = parseJson(resp);
                //log.trace("jres '%s'", jres);

                string type_msg = jres[ "type" ].get!string;

                //log.trace("type_msg '%s'", type_msg);

                if (type_msg != "ticket")
                    throw new HTTPStatusException(ResultCode.Not_Authorized);

                ticket.end_time = jres[ "end_time" ].get!long;
                ticket.id       = jres[ "id" ].get!string;
                ticket.user_uri = jres[ "user_uri" ].get!string;
                ticket.result   = cast(ResultCode)jres[ "result" ].get!long;

                //log.trace("new ticket= '%s'", ticket);
            }

            if (ticket.result != ResultCode.OK)
                throw new HTTPStatusException(ticket.result, text(ticket.result));

            return ticket;
        }
        finally
        {
        }
    }

    long get_operation_state(int module_id, long wait_op_id)
    {
        long res = -1;

        try
        {
            try
            {
                res = context.get_operation_state(cast(MODULE)module_id, wait_op_id);
            }
            catch (Throwable tr)
            {
                log.trace("ERR! REST:get_operation_state, %s \n%s ", tr.msg, tr.info);
            }
        }
        finally
        {
        }

        return res;
    }

    void send_to_module(int module_id, string msg)
    {
        try
        {
            long     res = -1;

            OpResult op_res;

            Json     jreq = Json.emptyObject;

            jreq[ "function" ]  = "send_to_module";
            jreq[ "module_id" ] = module_id;
            jreq[ "msg" ]       = msg;

            vibe.core.concurrency.send(wsc_server_task, jreq, Task.getThis());
            vibe.core.concurrency.receive((string res){ op_res = parseOpResult(res); });

            //log.trace("send:flush #e");
            if (op_res.result != ResultCode.OK)
                throw new HTTPStatusException(op_res.result, text(op_res.result));
        }
        finally
        {
        }
    }

    void flush(int module_id, long wait_op_id)
    {
        ulong    timestamp = Clock.currTime().stdTime() / 10;

        Json     jreq = Json.emptyObject;
        OpResult op_res;

        try
        {
            long res = -1;

            jreq[ "function" ]   = "flush";
            jreq[ "module_id" ]  = module_id;
            jreq[ "wait_op_id" ] = wait_op_id;

            vibe.core.concurrency.send(wsc_server_task, jreq, Task.getThis());
            vibe.core.concurrency.receive((string res){ op_res = parseOpResult(res); });

            if (op_res.result != ResultCode.OK)
                throw new HTTPStatusException(op_res.result, text(op_res.result));
        }
        finally
        {
            trail(null, null, "flush", jreq, "", op_res.result, timestamp);
        }
    }

    void set_trace(int idx, bool state)
    {
        context.set_trace(idx, state);
    }

    void backup(bool to_binlog)
    {
        ulong    timestamp = Clock.currTime().stdTime() / 10;

        long     res  = -1;
        Json     jreq = Json.emptyObject;
        OpResult op_res;

        try
        {
            jreq[ "function" ]  = "backup";
            jreq[ "to_binlog" ] = to_binlog;

            vibe.core.concurrency.send(wsc_server_task, jreq, Task.getThis());
            vibe.core.concurrency.receive((string res){ op_res = parseOpResult(res); });

            //log.trace("send:flush #e");
            if (op_res.result != ResultCode.OK)
                throw new HTTPStatusException(op_res.result, text(op_res.result));

            return;
        }
        finally
        {
            trail(null, null, "backup", jreq, "", op_res.result, timestamp);
        }
    }

    long count_individuals()
    {
        ulong    timestamp = Clock.currTime().stdTime() / 10;
        long     res;

        OpResult op_res;

        res           = context.count_individuals();
        op_res.result = ResultCode.OK;

        trail(null, null, "count_individuals", Json.emptyObject, text(res), op_res.result, timestamp);
        return res;
    }

    bool is_ticket_valid(string ticket_id)
    {
        ulong      timestamp = Clock.currTime().stdTime() / 10;
        bool       res;
        Ticket     *ticket;
        ResultCode rc;

        try
        {
            ticket = get_ticket(context, ticket_id);
            rc     = ticket.result;

            if (rc != ResultCode.OK)
                throw new HTTPStatusException(rc, text(rc));

            SysTime now = Clock.currTime();
            if (now.stdTime < ticket.end_time)
                res = true;
            else
                res = false;

            return res;
        }
        finally
        {
            trail(ticket_id, ticket.user_uri, "is_ticket_valid", Json.emptyObject, text(res), rc, timestamp);
        }
    }

    SearchResult query(string _ticket, string _query, string sort = null, string databases = null, bool reopen = false, int from = 0, int top = 10000,
                       int limit = 10000, bool trace = false)
    {
        ulong        timestamp = Clock.currTime().stdTime() / 10;

        SearchResult sr;
        Ticket       *ticket;
        ResultCode   rc;

        int          count = 0;

        void prepare_element(string uri)
        {
            //           if (count > 100)
//            {
            vibe.core.core.yield();
//                count = 0;
//            }
//            count++;
        }

        try
        {
            ticket = get_ticket(context, _ticket);
            rc     = ticket.result;

            if (rc != ResultCode.OK)
                return sr;

            sr = context.get_individuals_ids_via_query(ticket, _query, sort, databases, from, top, limit, null, trace); //&prepare_element);

            return sr;
        }
        finally
        {
            Json jreq = Json.emptyObject;
            jreq[ "query" ]     = _query;
            jreq[ "sort" ]      = sort;
            jreq[ "databases" ] = databases;
            jreq[ "reopen" ]    = reopen;
            jreq[ "from" ]      = from;
            jreq[ "top" ]       = top;
            jreq[ "limit" ]     = limit;

            trail(_ticket, ticket.user_uri, "query", jreq, text(sr.result), rc, timestamp);

            if (rc != ResultCode.OK)
                throw new HTTPStatusException(rc, text(rc));
        }
    }

    Json[] get_individuals(string _ticket, string[] uris)
    {
        ulong      timestamp = Clock.currTime().stdTime() / 10;

        Json[]     res;
        ResultCode rc;
        Json       args = Json.emptyArray;

        Ticket     *ticket;
        try
        {
            ticket = get_ticket(context, _ticket);
            rc     = ticket.result;
            if (rc != ResultCode.OK)
                return res;

            foreach (uri; uris)
            {
                try
                {
                    string cb = context.get_individual_as_binobj(ticket, uri, rc);
                    if (rc == ResultCode.OK)
                    {
                        Json res_i = Json.emptyObject;
                        cbor2json(&res_i, cb);
                        res ~= res_i;
                        args ~= uri;
                    }
                    else
                    {
                        log.trace("ERR! get_individuals: fail read uri=%s, code=%s", uri, rc);
                    }
                }
                catch (Throwable ex)
                {
                    rc = ResultCode.Internal_Server_Error;
                }
            }

            rc = ResultCode.OK;

            return res;
        }
        finally
        {
            Json jreq = Json.emptyObject;
            jreq[ "uris" ] = args;
            trail(_ticket, ticket.user_uri, "get_individuals", jreq, text(res), rc, timestamp);

            if (rc != ResultCode.OK)
                throw new HTTPStatusException(rc, text(rc));
        }
    }

    Consumer     cs0;
    Queue        main_queue;
    const string queue_state_prefix = "srv:queue-state-";

    Json get_individual(string _ticket, string uri, bool reopen = false)
    {
        ulong      timestamp = Clock.currTime().stdTime() / 10;

        Json       res = Json.emptyObject;
        ResultCode rc  = ResultCode.Internal_Server_Error;
        Ticket     *ticket;

        try
        {
            ticket = get_ticket(context, _ticket);
            rc     = ticket.result;

            if (rc != ResultCode.OK)
                return res;

            try
            {
                long ppos = uri.indexOf(queue_state_prefix);
                if (ppos == 0)
                {
                    string queue_name = uri[ queue_state_prefix.length..$ ];
                    log.trace("%s queue_name=%s", queue_state_prefix, queue_name);

                    main_queue = new Queue(queue_db_path, main_queue_name, Mode.R, log);
                    if (main_queue.open())
                    {
                        cs0 = new Consumer(main_queue, queue_db_path, queue_name, Mode.R, log);
                        if (!cs0.open())
                        {
                            rc = ResultCode.Invalid_Identifier;
                            return res;
                        }


                        // TODO: ? возможно для скорости следует переделать get_info на rawRead
                        main_queue.get_info();
                        cs0.get_info();

                        Individual indv_res;
                        indv_res.uri = uri;

                        indv_res.addResource(rdf__type, Resource(DataType.Uri, "v-s:AppInfo"));

                        indv_res.addResource("v-s:created", Resource(DataType.Datetime, Clock.currTime().toUnixTime()));
                        indv_res.addResource("srv:queue", Resource(DataType.Uri, "srv:" ~ queue_name));
                        indv_res.addResource("srv:total_count", Resource(DataType.Integer, main_queue.count_pushed));
                        indv_res.addResource("srv:current_count", Resource(DataType.Integer, cs0.count_popped));

                        res = individual_to_json(indv_res);

                        rc = ResultCode.OK;

                        cs0.close();
                        cs0 = null;

                        main_queue.close();
                        main_queue = null;
                    }

                    return res;
                }

                Individual[ string ] onto_individuals =
                    context.get_onto_as_map_individuals();

                Individual individual = onto_individuals.get(uri, Individual.init);

                if (individual != Individual.init)
                {
                    res = individual_to_json(individual);
                    rc  = ResultCode.OK;
                }
                else
                {
                    if (reopen)
                    {
                        context.reopen_ro_acl_storage_db();
                        context.reopen_ro_individuals_storage_db();
                    }

                    string cb = context.get_individual_as_binobj(ticket, uri, rc);
                    if (rc == ResultCode.OK)
                    {
                        res = Json.emptyObject;
                        cbor2json(&res, cb);
                    }
                }
            }
            catch (Throwable ex)
            {
                return res;
                //throw new HTTPStatusException(rc, ex.msg);
            }

            return res;
        }
        finally
        {
            Json jreq = Json.emptyObject;
            jreq[ "uri" ] = uri;
            trail(_ticket, ticket.user_uri, "get_individual", jreq, res.toString(), rc, timestamp);

            if (rc != ResultCode.OK)
            {
                throw new HTTPStatusException(rc, text(rc));
            }
        }
    }

    OpResult remove_individual(string _ticket, string uri, long assigned_subsystems, string event_id)
    {
        try
        {
            ulong      timestamp = Clock.currTime().stdTime() / 10;

            Ticket     *ticket;
            ResultCode rc = ResultCode.Internal_Server_Error;

            ticket = get_ticket(context, _ticket);
            rc     = ticket.result;

            if (rc != ResultCode.OK)
                throw new HTTPStatusException(rc, text(rc));

            Json individual_json = Json.emptyObject;

            individual_json[ "@" ] = uri;

            OpResult[] op_res = modify_individuals(context, "remove", _ticket, [ individual_json ], assigned_subsystems, event_id, timestamp);
            rc = op_res[ 0 ].result;

            if (rc != ResultCode.OK)
                throw new HTTPStatusException(rc, text(rc));

            return op_res[ 0 ];
        }
        catch (Throwable tr)
        {
            log.trace("ERR: error=[%s], stack=%s", tr.msg, tr.info);
            throw new HTTPStatusException(ResultCode.Internal_Server_Error, text(ResultCode.Internal_Server_Error));
        }
    }

    OpResult put_individual(string _ticket, Json individual_json, long assigned_subsystems, string event_id)
    {
        try
        {
            ulong      timestamp = Clock.currTime().stdTime() / 10;

            Ticket     *ticket;
            ResultCode rc = ResultCode.Internal_Server_Error;

            ticket = get_ticket(context, _ticket);
            rc     = ticket.result;

            if (rc != ResultCode.OK)
                throw new HTTPStatusException(rc, text(rc));

            OpResult[] op_res = modify_individuals(context, "put", _ticket, [ individual_json ], assigned_subsystems, event_id, timestamp);
            rc = op_res[ 0 ].result;

            if (rc != ResultCode.OK)
                throw new HTTPStatusException(rc, text(rc));

            return op_res[ 0 ];
        }
        catch (Throwable tr)
        {
            log.trace("ERR: error=[%s], stack=%s", tr.msg, tr.info);
            throw new HTTPStatusException(ResultCode.Internal_Server_Error, text(ResultCode.Internal_Server_Error));
        }
    }

    OpResult[] put_individuals(string _ticket, Json[] individuals_json, long assigned_subsystems, string event_id)
    {
        try
        {
            OpResult[] res;

            ulong      timestamp = Clock.currTime().stdTime() / 10;

            Ticket     *ticket;
            ResultCode rc = ResultCode.Internal_Server_Error;

            ticket = get_ticket(context, _ticket);
            rc     = ticket.result;

            if (rc != ResultCode.OK)
                throw new HTTPStatusException(rc, text(rc));

            res = modify_individuals(context, "put", _ticket, individuals_json, assigned_subsystems, event_id, timestamp);

            return res;
        }
        catch (Throwable tr)
        {
            log.trace("ERR: error=[%s], stack=%s", tr.msg, tr.info);
            throw new HTTPStatusException(ResultCode.Internal_Server_Error, text(ResultCode.Internal_Server_Error));
        }
    }

    OpResult add_to_individual(string _ticket, Json individual_json, long assigned_subsystems, string event_id)
    {
        ulong      timestamp = Clock.currTime().stdTime() / 10;
        Ticket     *ticket;
        ResultCode rc = ResultCode.Internal_Server_Error;

        ticket = get_ticket(context, _ticket);
        rc     = ticket.result;

        if (rc != ResultCode.OK)
            throw new HTTPStatusException(rc, text(rc));

        OpResult[] op_res = modify_individuals(context, "add_to", _ticket, [ individual_json ], assigned_subsystems, event_id, timestamp);
        rc = op_res[ 0 ].result;

        if (rc != ResultCode.OK)
            throw new HTTPStatusException(rc, text(rc));

        return op_res[ 0 ];
    }

    OpResult set_in_individual(string _ticket, Json individual_json, long assigned_subsystems, string event_id)
    {
        ulong      timestamp = Clock.currTime().stdTime() / 10;
        Ticket     *ticket;
        ResultCode rc = ResultCode.Internal_Server_Error;

        ticket = get_ticket(context, _ticket);
        rc     = ticket.result;

        if (rc != ResultCode.OK)
            throw new HTTPStatusException(rc, text(rc));

        OpResult[] op_res = modify_individuals(context, "set_in", _ticket, [ individual_json ], assigned_subsystems, event_id, timestamp);
        rc = op_res[ 0 ].result;

        if (rc != ResultCode.OK)
            throw new HTTPStatusException(rc, text(rc));

        return op_res[ 0 ];
    }

    OpResult remove_from_individual(string _ticket, Json individual_json, long assigned_subsystems, string event_id)
    {
        ulong      timestamp = Clock.currTime().stdTime() / 10;
        Ticket     *ticket;
        ResultCode rc = ResultCode.Internal_Server_Error;

        ticket = get_ticket(context, _ticket);
        rc     = ticket.result;

        if (rc != ResultCode.OK)
            throw new HTTPStatusException(rc, text(rc));

        OpResult[] op_res = modify_individuals(context, "remove_from", _ticket, [ individual_json ], assigned_subsystems, event_id, timestamp);
        rc = op_res[ 0 ].result;

        if (rc != ResultCode.OK)
            throw new HTTPStatusException(rc, text(rc));

        return op_res[ 0 ];
    }
}
//////////////////////////////

private TrailDBConstructor tdb_cons;
private bool               is_trail     = true;
private long               count_trails = 0;
private TrailDB            exist_trail;

void trail(string ticket_id, string user_id, string action, Json args, string result, ResultCode result_code, ulong start_time)
{
    if (!is_trail)
        return;

    try
    {
        ulong timestamp = Clock.currTime().stdTime() / 10;

        if (tdb_cons is null)
        {
            //try
            //{
            //	rename (trails_path ~ "/rest_trails_chunk.tdb", trails_path ~ "/rest_trails.tdb");
            //    exist_trail = new TrailDB(trails_path ~ "/rest_trails.tdb");
            //    //exist_trail.dontneed ();
            //}
            //catch (Throwable tr)
            //{
            //    log.trace("ERR! exist_trail: %s", tr.msg);
            //}

            log.trace("open trail db");

            string now = Clock.currTime().toISOExtString();
            now = now[ 0..indexOf(now, '.') + 4 ];

            tdb_cons =
                new TrailDBConstructor(trails_path ~ "/rest_trails_" ~ now,
                                       [ "ticket", "user_id", "action", "args", "result", "result_code", "duration" ]);

            //if (exist_trail !is null)
            //{
            //    log.trace("append to exist trail db");
            //    tdb_cons.append(exist_trail);
            //    log.trace("merge is ok");
            //}
        }

        RawUuid  uuid = randomUUID().data;

        string[] vals;

        vals ~= ticket_id;
        vals ~= user_id;
        vals ~= action;
        vals ~= text(args);
        vals ~= result;
        vals ~= text(result_code);
        vals ~= text(timestamp - start_time);

        tdb_cons.add(uuid, timestamp / 1000, vals);
        count_trails++;

        if (count_trails > 1000)
        {
            log.trace("flush trail db");
            tdb_cons.finalize();
            delete tdb_cons;
//            exist_trail.close ();
            tdb_cons     = null;
            count_trails = 0;
        }
    }
    catch (Throwable tr)
    {
        log.trace("ERR: error=[%s], stack=%s", tr.msg, tr.info);
    }
}

//////////////////////////////////////////////////////////////////// ws-server-transport
private OpResult[] modify_individuals(Context context, string cmd, string _ticket, Json[] individuals_json, long assigned_subsystems, string event_id,
                                      ulong start_time)
{
    OpResult[] op_res;

    Ticket     *ticket = get_ticket(context, _ticket);

    if (ticket.result != ResultCode.OK)
        throw new HTTPStatusException(ticket.result, text(ticket.result));

    if (wsc_server_task is Task.init)
        throw new HTTPStatusException(ResultCode.Internal_Server_Error, text(ResultCode.Internal_Server_Error));

//    Json juri = individual_json[ "@" ];
//    if (juri.type == Json.Type.undefined)
//        throw new HTTPStatusException(ResultCode.Internal_Server_Error, text(ResultCode.Internal_Server_Error));

    string res;
    Json   jreq = Json.emptyObject;
    jreq[ "function" ]            = cmd;
    jreq[ "ticket" ]              = _ticket;
    jreq[ "individuals" ]         = individuals_json;
    jreq[ "assigned_subsystems" ] = assigned_subsystems;
    jreq[ "event_id" ]            = event_id;

    vibe.core.concurrency.send(wsc_server_task, jreq, Task.getThis());
    vibe.core.concurrency.receive((string _res){ res = _res; op_res = parseOpResults(_res); });

    //if (trace_msg[ 500 ] == 1)
//    log.trace("put_individual #end : indv=%s, res=%s", individual_json, text(op_res));

    //if (op_res.result != ResultCode.OK)
    //    throw new HTTPStatusException(op_res.result, text(op_res.result));
//    Json juc = individual_json[ "v-s:updateCounter" ];

//    long update_counter = 0;
//    if (juc.type != Json.Type.undefined && juc.length > 0)
//        update_counter = juc[ 0 ][ "data" ].get!long;
    //set_updated_uid(juri.get!string, op_res.op_id, update_counter + 1);

    if (op_res.length == 1)
        trail(_ticket, ticket.user_uri, cmd, jreq, res, op_res[ 0 ].result, start_time);
    else
        trail(_ticket, ticket.user_uri, cmd, jreq, res, ResultCode.Not_Implemented, start_time);

    return op_res;
}


private OpResult parseOpResult(string str)
{
    OpResult res;

    res.result = ResultCode.Internal_Server_Error;

    if (str is null || str.length < 3)
        return res;

    try
    {
        Json jresp = parseJsonString(str);

        auto jtype = jresp[ "type" ];
        if (jtype.get!string == "OpResult")
        {
            res.op_id  = jresp[ "op_id" ].to!long;
            res.result = cast(ResultCode)jresp[ "result" ].to!int;
        }
    }
    catch (Throwable tr)
    {
        log.trace("ERR! parseOpResult: %s", tr.info);
    }

    return res;
}

private OpResult[] parseOpResults(string str)
{
    OpResult[] ress;

    if (str is null || str.length < 3)
        return ress;

    try
    {
        Json jresp = parseJsonString(str);

        auto jtype = jresp[ "type" ];
        if (jtype.get!string == "OpResult")
        {
            auto jdata = jresp[ "data" ];
            foreach (idata; jdata)
            {
                OpResult res;
                res.op_id  = idata[ "op_id" ].to!long;
                res.result = cast(ResultCode)idata[ "result" ].to!int;
                ress ~= res;
            }
        }
    }
    catch (Throwable tr)
    {
        log.trace("ERR! parseOpResult: %s", tr.info);
    }

    return ress;
}

private bool[ string ] external_users_ticket_id;

private Ticket *get_ticket(Context context, string ticket_id)
{
    Ticket *ticket = context.get_ticket(ticket_id);

    if (ticket.result == ResultCode.OK && is_external_users)
    {
        log.trace("check external user (%s)", ticket.user_uri);

        if (external_users_ticket_id.get(ticket_id, false) == false)
        {
            Individual user = context.get_individual(ticket, ticket.user_uri);
            if (user.exists("v-s:origin", Resource("External User")) == false)
            {
                log.trace("ERR! user (%s) is not external", ticket.user_uri);
                ticket.id     = "?";
                ticket.result = ResultCode.Not_Authorized;
            }
            else
            {
                log.trace("user is external (%s)", ticket.user_uri);
                external_users_ticket_id[ ticket.user_uri ] = true;
            }
        }
    }

    return ticket;
}

private Task wsc_server_task;

//////////////////////////////////////  WS
void connectToWS()
{
    WebSocket ws;

    while (ws is null)
    {
        try
        {
            auto ws_url = URL("ws://127.0.0.1:8091/ws");
            ws = connectWebSocket(ws_url);

            log.tracec("WebSocket connected to %s", ws_url);
        } catch (Throwable tr)
        {
            log.tracec("ERR! %s", tr.msg);
            core.thread.Thread.sleep(dur!("seconds")(10));
        }
    }

    wsc_server_task = Task.getThis();

    while (true)
    {
        Json msg;
        Task result_task_to;

        vibe.core.concurrency.receive(
                                      (Json _msg, Task _to)
                                      {
                                          msg = _msg;
                                          result_task_to = _to;
                                      }
                                      );

        //log.trace("sending '%s'", msg);
        ws.send(msg.toString());
        //log.trace("Ok");
        string resp = ws.receiveText();
        //log.trace("recv '%s'", resp);
        vibe.core.concurrency.send(result_task_to, resp);
        //log.trace("send to task ok");
    }
    //logFatal("Connection lost!");
}
