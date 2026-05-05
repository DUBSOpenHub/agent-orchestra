#!/usr/bin/env python3
import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path

STATE_PATH = Path('/Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/commanders/commander-004/swarm-state.json')
LEDGER_PATH = Path('/Users/greggcochran/dev/terminal-stampede/.stampede/run-20260430-180646/commanders/commander-004/child-agents.jsonl')
COMMANDER_ID = 'commander-004'
BANNED_MODELS = ['claude-haiku-4.5', 'gpt-5.4-mini', 'gpt-5-mini', 'gpt-4.1']


def now_iso():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace('+00:00', 'Z')


def atomic_json(path, data):
    tmp = path.with_name(f'.tmp-{path.name}')
    with tmp.open('w', encoding='utf-8') as fh:
        json.dump(data, fh, indent=2)
        fh.write('\n')
    os.replace(tmp, path)


def load_state():
    return json.loads(STATE_PATH.read_text())


def save_state(state):
    stamp = now_iso()
    state['updated_at'] = stamp
    state['last_heartbeat_at'] = stamp
    atomic_json(STATE_PATH, state)


def append_event(event):
    with LEDGER_PATH.open('a', encoding='utf-8') as fh:
        fh.write(json.dumps(event, separators=(',', ':')) + '\n')


def started(state, role):
    tel = state['telemetry']
    proof = state['launch_proof']
    stamp = now_iso()
    if proof['first_child_started_at'] is None:
        proof['first_child_started_at'] = stamp
    proof['last_child_started_at'] = stamp
    if role == 'squad_lead':
        proof['squad_leads_started'] += 1
        tel['squad_leads_launched'] += 1
        tel['squad_leads_running'] += 1
    elif role == 'worker':
        proof['workers_started'] += 1
        tel['workers_launched'] += 1
        tel['workers_running'] += 1


def completed(state, role, status, atom_id):
    tel = state['telemetry']
    is_success = status == 'success'
    if role == 'squad_lead':
        tel['squad_leads_running'] = max(0, tel['squad_leads_running'] - 1)
        key = 'squad_leads_completed' if is_success else 'squad_leads_failed'
        tel[key] += 1
    elif role == 'worker':
        tel['workers_running'] = max(0, tel['workers_running'] - 1)
        key = 'workers_completed' if is_success else 'workers_failed'
        tel[key] += 1
        if atom_id:
            tel['atoms_received'] += 1
    if not is_success:
        tel['children_failed'] += 1


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='cmd', required=True)

    common = argparse.ArgumentParser(add_help=False)
    common.add_argument('--child-id', required=True)
    common.add_argument('--parent-id')
    common.add_argument('--role', required=True)
    common.add_argument('--depth', type=int, required=True)
    common.add_argument('--agent-type', required=True)
    common.add_argument('--model', required=True)
    common.add_argument('--workers-target', type=int)
    common.add_argument('--can-launch')
    common.add_argument('--agent-id')

    sub.add_parser('launch_requested', parents=[common])
    sub.add_parser('launch_started', parents=[common])

    done = sub.add_parser('completed')
    done.add_argument('--child-id', required=True)
    done.add_argument('--parent-id')
    done.add_argument('--role', required=True)
    done.add_argument('--status', required=True)
    done.add_argument('--atom-id')

    phase = sub.add_parser('phase')
    phase.add_argument('--phase', required=True)
    phase.add_argument('--status')

    args = parser.parse_args()
    state = load_state()

    if args.cmd in ('launch_requested', 'launch_started'):
        event = {
            'ts': now_iso(),
            'event': args.cmd,
            'commander_id': COMMANDER_ID,
            'child_id': args.child_id,
            'role': args.role,
            'depth': args.depth,
            'agent_type': args.agent_type,
            'model': args.model,
        }
        if args.parent_id:
            event['parent_id'] = args.parent_id
        if args.workers_target is not None:
            event['workers_target'] = args.workers_target
        if args.can_launch is not None:
            event['can_launch'] = args.can_launch.lower() == 'true'
        if args.agent_id:
            event['agent_id'] = args.agent_id
        append_event(event)
        if args.cmd == 'launch_started':
            if args.model in BANNED_MODELS:
                state['status'] = 'partial'
            started(state, args.role)
            save_state(state)
        else:
            save_state(state)
        return

    if args.cmd == 'completed':
        event = {
            'ts': now_iso(),
            'event': 'completed',
            'child_id': args.child_id,
            'status': args.status,
        }
        if args.parent_id:
            event['parent_id'] = args.parent_id
        if args.atom_id:
            event['atom_id'] = args.atom_id
        append_event(event)
        completed(state, args.role, args.status, args.atom_id)
        save_state(state)
        return

    if args.cmd == 'phase':
        state['phase'] = args.phase
        if args.status:
            state['status'] = args.status
        save_state(state)
        return


if __name__ == '__main__':
    main()
