/**
 * настройка логгирования
 */
module veda.core.log_msg;

private import util.logger;

byte[ 1000 ] trace_msg;

// last id = 500
long T_REST_1 = 500;
long T_ACL_1 = 111;
long T_ACL_2 = 112;
long T_ACL_3 = 113;

static this()
{
    trace_msg      = 0;
    trace_msg[ 2 ] = 0;
    trace_msg[ 3 ] = 0;

    // basis logging
    trace_msg[ 0 ]  = 1;
    trace_msg[ 10 ] = 1;
    trace_msg[ 68 ] = 1;
    trace_msg[ 69 ] = 1;

    version (trace)
        trace_msg[] = 1;     // полное логгирование

	version (trace_acl)
	{
    	trace_msg[ T_ACL_1 ] = 1;
    	trace_msg[ T_ACL_2 ] = 1;
    	trace_msg[ T_ACL_3 ] = 1;
	}
}

void set_message(int idx)
{
    trace_msg[ idx ] = 1;
}

void set_all_messages()
{
    trace_msg = 1;
}

void unset_all_messages()
{
    trace_msg = 0;
}

void unset_message(int idx)
{
    trace_msg[ idx ] = 0;
}


void set_trace(int idx, bool state)
{
    if (idx < 0 || idx >= trace_msg.length)
        return;

    if (idx == 0)
        trace_msg = state;
    else
        trace_msg[ idx ] = state;
}