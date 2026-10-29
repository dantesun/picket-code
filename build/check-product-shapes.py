#!/usr/bin/env python3
"""Check that build/product.json keeps the shapes upstream code expects.

Upstream code reads product.json without guards: it iterates arrays and
dereferences objects. Two startup crashes shipped from this overlay because of
that (the extension scanner iterated a missing array; the remote-tunnel
recommendation read `.extension` off an empty object), so the overlay is checked
against three rules instead of trusted:

  A. an override keeps the upstream JSON type;
  B. a key may only disappear when its consumers are guarded (SAFE_REMOVALS);
  C. an added key never carries an empty container - a truthiness probe passes,
     then the next line dereferences a sub-field that is not there.

Usage: check-product-shapes.py <upstream-product.json> <overlay-product.json>
Exit codes: 0 ok, 3 shape mismatch, 2 usage/setup error.
"""
import json
import sys

JSON_TYPE = {
    dict: 'object',
    list: 'array',
    str: 'string',
    bool: 'boolean',
    int: 'number',
    float: 'number',
}

# Keys the overlay deletes on purpose. Each entry names the guard that makes the
# removal safe, so a future removal cannot be added "to make it quiet".
SAFE_REMOVALS = {
    # the account provider is never registered and its waiters are released;
    # chat setup / status bar / onboarding / extension management all guard on a
    # missing agent (58-agenthost-clean-product-config.patch)
    'defaultChatAgent': '58-agenthost-clean-product-config.patch',
    # every consumer narrows on Array.isArray / typeof / `?.`
    # (authenticationAccessService, authenticationUsageService, chatLanguageModelActions)
    'trustedExtensionAuthAccess': 'consumers narrow with Array.isArray / typeof / ?.',
}


def check(upstream: dict, overlay: dict) -> list[str]:
    errors: list[str] = []
    for key, value in overlay.items():
        if key not in upstream:
            if value == {} or value == []:
                kind = JSON_TYPE[type(value)]
                errors.append(
                    f'{key}: adds an empty {kind} that upstream does not define '
                    f'(truthiness checks pass, sub-fields do not exist)')
            continue
        if value is None:
            upstream_type = JSON_TYPE.get(type(upstream[key]))
            if upstream_type in ('array', 'object') and key not in SAFE_REMOVALS:
                errors.append(
                    f'{key}: removes an upstream {upstream_type} key whose consumers are '
                    f'not guarded (add it to SAFE_REMOVALS with the guard that makes it safe)')
            continue
        want = JSON_TYPE.get(type(upstream[key]))
        got = JSON_TYPE.get(type(value))
        if want and got and want != got:
            errors.append(f'{key}: overlay has {got}, upstream has {want}')
    return errors


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__.strip().splitlines()[-1], file=sys.stderr)
        return 2
    try:
        upstream = json.load(open(argv[1], encoding='utf-8'))
        overlay = json.load(open(argv[2], encoding='utf-8'))
    except (OSError, ValueError) as exc:
        print(f'FATAL: cannot read product.json: {exc}', file=sys.stderr)
        return 2

    errors = check(upstream, overlay)
    if errors:
        print('FATAL: product.json overlay does not match the upstream shapes:', file=sys.stderr)
        for error in errors:
            print('  ' + error, file=sys.stderr)
        return 3
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
