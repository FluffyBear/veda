module veda.storage_rest;

import vibe.d;
import veda.pacahon_driver;

import std.stdio, std.datetime, std.conv, std.string, std.datetime, std.file;
import vibe.core.core, vibe.core.log, vibe.core.task, vibe.inet.mimetypes;
import properd;

import type;
import pacahon.context;
import pacahon.know_predicates;
import onto.onto;
import onto.individual;
import onto.resource;
import onto.lang;
import veda.util;


public const string veda_schema__File          = "v-s:File";
public const string veda_schema__fileName      = "v-s:fileName";
public const string veda_schema__fileSize      = "v-s:fileSize";
public const string veda_schema__fileThumbnail = "v-s:fileThumbnail";
public const string veda_schema__fileURI       = "v-s:fileURI";

const string        attachments_db_path = "./data/files";

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

    @path("authenticate") @method(HTTPMethod.GET)
    Ticket authenticate(string login, string password);

    @path("is_ticket_valid") @method(HTTPMethod.GET)
    bool is_ticket_valid(string ticket);

    @path("wait_pmodule") @method(HTTPMethod.GET)
    void wait_pmodule(int pmodule_id);

    @path("set_trace") @method(HTTPMethod.GET)
    void set_trace(int idx, bool state);

    @path("backup") @method(HTTPMethod.GET)
    void backup();

    @path("count_individuals") @method(HTTPMethod.GET)
    long count_individuals();

    @path("query") @method(HTTPMethod.GET)
    string[] query(string ticket, string query, string sort = null);

    @path("get_individuals") @method(HTTPMethod.POST)
    Json[] get_individuals(string ticket, string[] uris);

    @path("get_individual") @method(HTTPMethod.GET)
    Json get_individual(string ticket, string uri);

//    @path("put_individuals") @method(HTTPMethod.PUT)
//    int put_individuals(string ticket, Json[] individuals);

    @path("put_individual") @method(HTTPMethod.PUT)
    int put_individual(string ticket, Json individual, bool wait_for_indexing);

//    @path("get_property_values") @method(HTTPMethod.GET)
//    Json[] get_property_values(string ticket, string uri, string property_uri);

//    @path("execute_script") @method(HTTPMethod.POST)
//    string[ 2 ] execute_script(string script);
}


struct Worker
{
    std.concurrency.Tid tid;
    int                 id;
    bool                ready    = true;
    bool                complete = false;

    // worker result data
    ResultCode          rc;
    union
    {
        string[] res_string_array;
        Json[]   res_json_array;
        long     res_long;
    }
}


class VedaStorageRest : VedaStorageRest_API
{
    private Context    context;
    private Worker *[] pool;
    string[ string ] properties;
    int                count_thread;

    int                last_used_tid = 0;

    this(std.concurrency.Tid[] _pool, Context _local_context, ref string[ string ] _properties)
    {
        properties   = _properties;
        count_thread = properties.as!(int)("count_thread");

        context = _local_context;
        foreach (idx, tid; _pool)
        {
            Worker *worker = new Worker(tid, cast(int)idx, true, false, ResultCode.No_Content);
            pool ~= worker;
        }
    }

/////////////////////////////////////////////////////////////////////////////////////////////////////////////

    private std.concurrency.Tid getFreeTid()
    {
        writeln("#1");
        Worker *res;
        last_used_tid++;

        if (last_used_tid >= pool.length)
            last_used_tid = 0;

        res = pool[ last_used_tid ];

        return res.tid;
    }

    private Worker *get_worker(int idx)
    {
        return pool[ idx ];
    }

    private Worker *allocate_worker()
    {
        //writeln ("@1 request worker");
        Worker *worker = get_free_worker();

        while (worker is null)
        {
            yield();
            worker = get_free_worker();
        }
        //writeln ("@2 allocate worker ", worker.id);
        worker.ready    = false;
        worker.complete = false;
        return worker;
    }

    private Worker *get_free_worker()
    {
        Worker *res = null;

        for (int idx = 0; idx < pool.length; idx++)
        {
            res = pool[ idx ];
            if (res.ready == true)
                return res;
        }
        //writeln ("--- ALL WORKERS BUSY ----");
        return null;
    }

    private string[] put_another_get_my(int another_worker_id, string[] another_res, ResultCode another_result_code, Worker *my_worker)
    {
        // сохраняем результат
        Worker *another_worker = get_worker(another_worker_id);

        another_worker.res_string_array = another_res;
        another_worker.rc               = another_result_code;
        another_worker.complete         = true;

        // цикл по ожиданию своего результата
        while (my_worker.complete == false)
            yield();

        string[] res = my_worker.res_string_array.dup;

        my_worker.complete = false;
        my_worker.ready    = true;

        if (my_worker.rc != ResultCode.OK)
            throw new HTTPStatusException(my_worker.rc);

        //writeln ("free worker ", my_worker.id);

        return res;
    }

    private Json[] put_another_get_my(int another_worker_id, Json[] another_res, ResultCode another_result_code,
                                      Worker *my_worker)
    {
        // сохраняем результат
        Worker *another_worker = get_worker(another_worker_id);

        another_worker.res_json_array = another_res;
        another_worker.rc             = another_result_code;
        another_worker.complete       = true;

        // цикл по ожиданию своего результата
        while (my_worker.complete == false)
            yield();

        Json[] res = my_worker.res_json_array.dup;

        my_worker.complete = false;
        my_worker.ready    = true;

        if (my_worker.rc != ResultCode.OK)
            throw new HTTPStatusException(my_worker.rc);

        //writeln ("free worker ", my_worker.id);

        return res;
    }

    private long put_another_get_my(int another_worker_id, long another_res, ResultCode another_result_code,
                                    Worker *my_worker)
    {
        // сохраняем результат
        Worker *another_worker = get_worker(another_worker_id);

        another_worker.res_long = another_res;
        another_worker.rc       = another_result_code;
        another_worker.complete = true;

        // цикл по ожиданию своего результата
        while (my_worker.complete == false)
            yield();

        long res = my_worker.res_long;

        if (my_worker.rc != ResultCode.OK)
            throw new HTTPStatusException(my_worker.rc);

        my_worker.complete = false;
        my_worker.ready    = true;

        return res;
    }

/////////////////////////////////////////////////////////////////////////////////////////////////////////////

    void fileManager(HTTPServerRequest req, HTTPServerResponse res)
    {
        writeln("@v req.path=", req.path);

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

        writeln("@v uri=", uri);

        string ticket = req.cookies.get("ticket", "");

        writeln("@v ticket=", ticket);

        if (uri.length > 3 && ticket !is null)
        {
            //Tid my_task = Task.getThis();

            //if (my_task is Tid.init)
            //    return;

            immutable(Individual)[] individual;
            std.concurrency.send(getFreeTid(), Command.Get, Function.Individual, uri, ticket, std.concurrency.thisTid);
            //yield();
            ResultCode rc;
            std.concurrency.receive((immutable(Individual)[] _individuals, ResultCode _rc) { individual = _individuals; rc = _rc; });

            if (rc != ResultCode.OK)
                throw new HTTPStatusException(rc);

            if (individual.length == 0)
                return;

            Individual file_info = cast(Individual)individual[ 0 ];

            writeln("@v file_info=", file_info);
            auto fileServerSettings = new HTTPFileServerSettings;
            fileServerSettings.encodingFileExtension = [ "jpeg":".JPG" ];

            HTTPServerRequestDelegate dg =
                serveStaticFile(attachments_db_path ~ "/" ~ file_info.getFirstResource(veda_schema__fileURI).get!string,
                                fileServerSettings);
            string originFileName = file_info.getFirstResource(veda_schema__fileName).get!string;

            writeln("@v originFileName=", originFileName);
            writeln("@v getMimeTypeForFile(originFileName)=", getMimeTypeForFile(originFileName));

            res.headers[ "Content-Disposition" ] = "Content-Disposition: attachment; filename=\"" ~ originFileName ~ "\"";


            res.contentType = getMimeTypeForFile(originFileName);
            dg(req, res);
        }
    }

    override :

    Json get_rights(string _ticket, string uri)
    {
        ResultCode rc;
        ubyte      res;

        Ticket     *ticket = context.get_ticket(_ticket);

        rc = ticket.result;
        if (rc == ResultCode.OK)
        {
            res = context.get_rights(ticket, uri);
        }

        Individual indv_res;
        indv_res.uri = "_";

        indv_res.addResource(rdf__type, Resource(DataType.Uri, veda_schema__PermissionStatement));

        if ((res & Access.can_read) > 0)
            indv_res.addResource(veda_schema__canRead, Resource(true));

        if ((res & Access.can_update) > 0)
            indv_res.addResource(veda_schema__canUpdate, Resource(true));

        if ((res & Access.can_delete) > 0)
            indv_res.addResource(veda_schema__canDelete, Resource(true));

        if ((res & Access.can_create) > 0)
            indv_res.addResource(veda_schema__canCreate, Resource(true));


        Json json = individual_to_json(indv_res);
        return json;
    }

    Json[] get_rights_origin(string ticket, string uri)
    {
        immutable(Individual)[] individuals;
        //Tid                     my_task = Task.getThis();

        //if (my_task !is Tid.init)
        {
            std.concurrency.send(getFreeTid(), Command.Get, Function.RightsOrigin, uri, ticket, std.concurrency.thisTid);
            //yield();
            individuals = std.concurrency.receiveOnly!(immutable(Individual)[]);
        }

        Json[] json = Json[].init;
        foreach (individual; individuals)
            json ~= individual_to_json(individual);

        return json;
    }

    Ticket authenticate(string login, string password)
    {
        Ticket ticket = context.authenticate(login, password);

        if (ticket.result != ResultCode.OK)
            throw new HTTPStatusException(ticket.result);
        return ticket;
    }

    void wait_pmodule(int thread_id)
    {
        context.wait_thread(cast(P_MODULE)thread_id);
        if (thread_id == P_MODULE.fulltext_indexer)
        {
            context.reopen_ro_fulltext_indexer_db();
        }
    }

    void set_trace(int idx, bool state)
    {
        context.set_trace(idx, state);
    }

    void backup()
    {
        ResultCode rc = ResultCode.OK;
        int        recv_worker_id;

        long       res = -1;

        Worker     *worker = allocate_worker();

        std.concurrency.send(getFreeTid(), Command.Execute, Function.Backup, worker.id, std.concurrency.thisTid);
        yield();
        std.concurrency.receive((bool _res, int _recv_worker_id) { res = _res; recv_worker_id = _recv_worker_id; });

        if (recv_worker_id == worker.id)
        {
            worker.complete = false;
            worker.ready    = true;

            if (rc != ResultCode.OK)
                throw new HTTPStatusException(rc);
        }
        else
        {
            res = put_another_get_my(recv_worker_id, res, rc, worker);
        }
        return;
    }

    long count_individuals()
    {
        ResultCode rc = ResultCode.OK;
        int        recv_worker_id;

        long       res = -1;

        Worker     *worker = allocate_worker();

        std.concurrency.send(worker.tid, Command.Execute, Function.CountIndividuals, worker.id, std.concurrency.thisTid);
        yield();
        std.concurrency.receive((long _res, int _recv_worker_id) { res = _res; recv_worker_id = _recv_worker_id; });

        if (recv_worker_id == worker.id)
        {
            worker.complete = false;
            worker.ready    = true;

            if (rc != ResultCode.OK)
                throw new HTTPStatusException(rc);
        }
        else
        {
            res = put_another_get_my(recv_worker_id, res, rc, worker);
        }
        return res;
    }

    bool is_ticket_valid(string ticket)
    {
        bool res = context.is_ticket_valid(ticket);

        return res;
    }

    string[] query(string ticket, string query, string sort)
    {
        ResultCode rc;
        int        recv_worker_id;

        string[]   individuals_ids;

        Worker     *worker = allocate_worker();

        std.concurrency.send(worker.tid, Command.Get, Function.IndividualsIdsToQuery, query, sort, ticket, worker.id,
                             std.concurrency.thisTid);
        yield();

        std.concurrency.receive((immutable(
                                           string)[] _individuals_ids, ResultCode _rc, int _recv_worker_id) { individuals_ids =
                                                                                                                  cast(string[])_individuals_ids; rc = _rc; recv_worker_id = _recv_worker_id;
                                });

        if (recv_worker_id == worker.id)
        {
            worker.complete = false;
            worker.ready    = true;

            if (rc != ResultCode.OK)
                throw new HTTPStatusException(rc);
        }
        else
        {
            individuals_ids = put_another_get_my(recv_worker_id, individuals_ids, rc, worker);
        }
        return individuals_ids;
    }

    Json[] get_individuals(string ticket, string[] uris)
    {
        ResultCode rc;
        int        recv_worker_id;

        Json[]     res;

        Worker     *worker = allocate_worker();

        std.concurrency.send(worker.tid, Command.Get, Function.Individuals, uris.idup, ticket, worker.id, std.concurrency.thisTid);
        yield();
        std.concurrency.receive((immutable(
                                           Json)[] _res, ResultCode _rc, int _recv_worker_id) { res = cast(Json[])_res; rc = _rc; recv_worker_id = _recv_worker_id;
                                });

        if (recv_worker_id == worker.id)
        {
            worker.complete = false;
            worker.ready    = true;

            if (rc != ResultCode.OK)
                throw new HTTPStatusException(rc);
        }
        else
        {
            res = put_another_get_my(recv_worker_id, res, rc, worker);
        }

        return res;
    }

    Json get_individual(string _ticket, string uri)
    {
        ResultCode rc;
        int        recv_worker_id;

        if (count_thread > 0)
        {
            Json[] res;

            Worker *worker = allocate_worker();

            std.concurrency.send(worker.tid, Command.Get, Function.Individual, uri, "", _ticket, worker.id, std.concurrency.thisTid);
            yield();
            std.concurrency.receive((immutable(
                                               Json)[] _res, ResultCode _rc, int _recv_worker_id) { res = cast(Json[])_res; rc = _rc; recv_worker_id = _recv_worker_id;
                                    });

            if (recv_worker_id == worker.id)
            {
                //writeln ("free worker ", worker.id);
                worker.complete = false;
                worker.ready    = true;

                if (rc != ResultCode.OK)
                    throw new HTTPStatusException(rc);
            }
            else
            {
                res = put_another_get_my(recv_worker_id, res, rc, worker);
            }

            if (res.length > 0)
                return res[ 0 ];
            else
                return Json.init;
        }
        else
        {
            Individual res;

            immutable(Individual)[ string ] onto_individuals =
                context.get_onto_as_map_individuals();

            immutable(Individual) individual = onto_individuals.get(uri, immutable(Individual).init);

            if (individual != immutable(Individual).init)
            {
                rc  = ResultCode.OK;
                res = cast(Individual)individual;
            }
            else
            {
                Ticket *ticket = context.get_ticket(_ticket);
                rc = ticket.result;
                if (rc == ResultCode.OK)
                {
                    Individual ii = context.get_individual(ticket, uri);
                    if (ii.getStatus() == ResultCode.OK)
                        res = ii;
                    else
                        rc = ii.getStatus();
                }
            }

            if (rc != ResultCode.OK)
                throw new HTTPStatusException(rc);

            Json json = individual_to_json(res);
            return json;
        }
    }

    int put_individual(string _ticket, Json individual_json, bool wait_for_indexing)
    {
        Individual indv = json_to_individual(individual_json);
        ResultCode rc;
        Ticket     *ticket = context.get_ticket(_ticket);

        if (ticket.result == ResultCode.OK)
        {
            context.put_individual(ticket, indv.uri, indv, wait_for_indexing);
        }

        if (rc != ResultCode.OK)
            throw new HTTPStatusException(rc);
        return rc.to!int;

        //return ResultCode.Service_Unavailable.to!int;
    }

//    int put_individuals(string ticket, Json[] individuals_json)
//    {
//    //Tid my_task = Task.getThis();
//    //if (my_task !is Tid.init) {
//        immutable(Individual)[] ind;
//        ind ~= individual.idup;
//        std.concurrency.send(getFreeTid (), Command.Put, Function.Individuals, ticket, uri, ind, std.concurrency.thisTid);
//        ResultCode res = std.concurrency.receiveOnly!(ResultCode);
//        return res;
//    }
//        return ResultCode.Service_Unavailable.to!int;
//    }

//    Json[] get_property_values(string ticket, string uri, string property_uri)
//    {
//    //Tid my_task = Task.getThis();
//        string res;

//    //if (my_task !is Tid.init) {
//        std.concurrency.send(getFreeTid (), Command.Get, Function.PropertyOfIndividual, uri, property_uri, lang, std.concurrency.thisTid);
//        res = std.concurrency.receiveOnly!(string);
//    }
//    return res;
//        return Json[].init;
//    }

//    string[ 2 ] execute_script(string script)
//    {
//        string[ 2 ] res;
//        //Tid my_task = Task.getThis();
//        //if (my_task !is Tid.init)
//        {
//            std.concurrency.send(getFreeTid(), Command.Execute, Function.Script, script, std.concurrency.thisTid);
//            //yield();
//            res = std.concurrency.receiveOnly!(string[ 2 ]);
//        }
//
//        return res;
//    }
}
