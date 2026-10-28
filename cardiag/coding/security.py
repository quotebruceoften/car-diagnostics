"""Seed/key algorithms for UDS SecurityAccess (service 0x27).

Real algorithms are manufacturer (often module) specific and are not shipped
here. Register your own with :func:`register`, or reference one from a
coding profile as ``"package.module:function"``. The function receives the
seed bytes and the requested (odd) security level and returns the key bytes.
"""
from __future__ import annotations

import importlib
from typing import Callable

from ..errors import CodingError

KeyFunction = Callable[[bytes, int], bytes]

_REGISTRY: dict[str, KeyFunction] = {}


def register(name: str):
    def decorator(fn: KeyFunction) -> KeyFunction:
        _REGISTRY[name] = fn
        return fn

    return decorator


def get(name: str) -> KeyFunction:
    if name in _REGISTRY:
        return _REGISTRY[name]
    if ":" in name:
        module_name, _, attr = name.partition(":")
        try:
            fn = getattr(importlib.import_module(module_name), attr)
        except (ImportError, AttributeError) as exc:
            raise CodingError(f"cannot load security algorithm {name!r}: {exc}") from exc
        if not callable(fn):
            raise CodingError(f"security algorithm {name!r} is not callable")
        return fn
    raise CodingError(f"unknown security algorithm {name!r} (known: {', '.join(sorted(_REGISTRY))})")


def available() -> list[str]:
    return sorted(_REGISTRY)


@register("demo_xor")
def demo_xor(seed: bytes, level: int) -> bytes:
    """Toy algorithm used by the built-in simulator. Not used by any real car."""
    return bytes(b ^ 0xA5 ^ ((i * 0x3B + level) & 0xFF) for i, b in enumerate(seed))
