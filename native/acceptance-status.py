#!/usr/bin/env python3
"""Validate diagnostic evidence. No device operations or mutable global state."""
import json
import sys
from datetime import datetime, timezone


def valid(data, request_id, phase, dataset, expected_token='', count='', launched_epoch=0):
    try:
        stamp = datetime.fromisoformat(data['timestamp'].replace('Z', '+00:00')).timestamp()
        if not request_id or data.get('requestID') != request_id:
            return False
        if data.get('phase') != phase or data.get('dataset') != dataset:
            return False
        if not float(launched_epoch) <= stamp <= datetime.now(timezone.utc).timestamp() + 5:
            return False
        if phase != 'cleaned':
            token = data.get('expectedToken')
            if not token or token != data.get('observedToken'):
                return False
            version, revision = token.split('/')
            if int(version) <= 0 or int(revision) < 0:
                return False
            if expected_token and token != expected_token:
                return False
        if data.get('alarmsVerified') is not True:
            return False
        if count and data.get('alarmCount') != int(count):
            return False
        return True
    except (ValueError, TypeError, KeyError, AttributeError):
        return False


if __name__ == '__main__':
    try:
        with open(sys.argv[1], encoding='utf-8') as handle:
            result = valid(json.load(handle), *sys.argv[2:])
        sys.exit(0 if result else 1)
    except (OSError, ValueError, TypeError):
        sys.exit(1)
