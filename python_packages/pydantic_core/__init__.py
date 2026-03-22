"""
Stub pydantic_core module, not actually used by tiddl directly,
but prevents import errors if pydantic tries to check for it.
"""
__version__ = "2.99.0"

class PydanticUndefinedType:
    pass

PydanticUndefined = PydanticUndefinedType()
