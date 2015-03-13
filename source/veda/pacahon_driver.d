module veda.pacahon_driver;

import std.stdio, std.datetime, std.conv, std.string, std.variant, std.concurrency;
import vibe.data.json;

import pacahon.server;
import pacahon.context;
import pacahon.thread_context;
import pacahon.know_predicates;
import type;
import onto.onto;
import onto.individual;
import onto.resource;
import onto.lang;

import veda.util;

enum Command
{
    Get     = 1,
    Is      = 2,
    Put     = 3,
    Set     = 3,
    Execute = 4,
    Wait    = 5
}

enum Function
{
    Individual,
    Individuals,
    PropertyOfIndividual,
    IndividualsToQuery,
    IndividualsIdsToQuery,
    NewTicket,
    TicketValid,
    Script,
    PModule,
    Trace,
    Backup,
    CountIndividuals,
    Rights,
    RightsOrigin
}

public void core_thread()
{
    Context context;
    string  thread_name = "veda" ~ text(std.uuid.randomUUID().toHash())[ 0..5 ];

    core.thread.Thread.getThis().name = thread_name;

    context = new PThreadContext(props_file_path, thread_name);

    writeln("--- START VEDA STORAGE THREAD LISTENER --- " ~ thread_name);

    immutable(Individual) _empty_iIndividual = (immutable(Individual)).init;
    Resources _empty_Resources = Resources.init;

    while (true)
    {
        receive(
                (Command cmd, Function fn, int worker_id, Tid tid)
                {
                    if (tid != Tid.init)
                    {
                        if (cmd == Command.Execute && fn == Function.Backup)
                        {
                            context.backup();
                            send(tid, true, worker_id);
                        }
                        else if (cmd == Command.Execute && fn == Function.CountIndividuals)
                        {
                            long count = context.count_individuals();
                            send(tid, count, worker_id);
                        }
                    }
                },
                (Command cmd, Function fn, immutable(string)[] arg1, string arg2, int worker_id, Tid tid)
                {
                    if (tid != Tid.init)
                    {
                        if (cmd == Command.Get && fn == Function.Individuals)
                        {
                            immutable(Json)[] res = Json[].init;

                            Ticket *ticket = context.get_ticket(arg2);
                            if (ticket.result == ResultCode.OK)
                            {
                                foreach (indv; context.get_individuals(ticket, arg1.dup))
                                {
                                    Json jj = individual_to_json(indv);
                                    res ~= cast(immutable)jj;
                                }
                            }
                            send(tid, res, ticket.result, worker_id);
                        }
                    }
                },
                (Command cmd, Function fn, string arg1, string arg2, string _ticket, int worker_id, Tid tid)
                {
                    if (tid != Tid.init)
                    {
                        if (cmd == Command.Get && fn == Function.IndividualsIdsToQuery)
                        {
                            //writeln ("@! ", thread_name);
                            Ticket *ticket = context.get_ticket(_ticket);

                            if (ticket.result == ResultCode.OK)
                            {
                                immutable(string)[] uris = context.get_individuals_ids_via_query(ticket, arg1, arg2);
                                // writeln ("@!1", uris);
                                send(tid, uris, ticket.result, worker_id);
                            }
                            else
                            {
                                immutable(string)[] uris;
                                send(tid, uris, ticket.result, worker_id);
                            }
                        }

                        else if (cmd == Command.Get && fn == Function.Individual)
                        {
                            immutable(Json)[] res = Json[].init;

                            immutable(Individual)[ string ] onto_individuals =
                                context.get_onto_as_map_individuals();

                            immutable(Individual) individual = onto_individuals.get(arg1, _empty_iIndividual);
                            ResultCode rc;
                            if (individual != _empty_iIndividual)
                            {
                                rc = ResultCode.OK;
                                res ~= cast(immutable)individual_to_json(individual);
                            }
                            else
                            {
                                Ticket *ticket = context.get_ticket(_ticket);
                                rc = ticket.result;
                                if (rc == ResultCode.OK)
                                {
                                    Individual ii = context.get_individual(ticket, arg1);
                                    if (ii.getStatus() == ResultCode.OK)
                                        res ~= cast(immutable)individual_to_json(ii);
                                    else
                                        rc = ii.getStatus();
                                }
                            }
                            send(tid, res, rc, worker_id);
                        }
                    }
                },
                (Command cmd, Function fn, string arg1, string arg2, Tid tid)
                {
                    if (tid != Tid.init)
                    {
                        if (cmd == Command.Get && fn == Function.Rights)
                        {
                            ResultCode rc;

                            Ticket *ticket = context.get_ticket(arg2);
                            ubyte res;
                            rc = ticket.result;
                            if (rc == ResultCode.OK)
                            {
                                res = context.get_rights(ticket, arg1);
                            }
                            send(tid, res);
                        }
                        else if (cmd == Command.Get && fn == Function.RightsOrigin)
                        {
                            immutable(Individual)[] res;
                            void trace(string resource_group, string subject_group, string right)
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

                                res ~= indv_res.idup;
                            }

                            ResultCode rc;

                            Ticket *ticket = context.get_ticket(arg2);
                            rc = ticket.result;
                            if (rc == ResultCode.OK)
                            {
                                context.get_rights_origin(ticket, arg1, &trace);
                            }
                            send(tid, res);
                        }
                    }
                },
                (Command cmd, Function fn, string args, Tid tid) {
                    // writeln("Tid=", cast(void *)tid);
                    if (tid !is Tid.init)
                    {
                        if (cmd == Command.Execute && fn == Function.Script)
                        {
                            send(tid, context.execute_script(args));
                        }
                    }
                },
                (Variant v) { writeln("pacahon_driver::Received some other type. ", v); }
                );
    }
}

