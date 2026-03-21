"""
Minimal pydantic v2 shim for iOS (no pydantic-core dependency).

Provides just enough of pydantic's API for tiddl to work:
- BaseModel with model_validate / model_validate_json
- field_validator decorator
- model_post_init lifecycle hook
- ConfigDict (no-op)
"""

import json
from typing import Any, ClassVar, Optional, get_type_hints

__version__ = "2.99.0"  # Fake version to satisfy version checks
VERSION = __version__


class ConfigDict(dict):
    """No-op configuration dictionary."""
    pass


class FieldInfo:
    def __init__(self, default=..., alias=None, **kwargs):
        self.default = default
        self.alias = alias
        self.extra = kwargs


def Field(default=..., *, alias=None, **kwargs):
    return FieldInfo(default=default, alias=alias, **kwargs)


def field_validator(*fields, mode="after"):
    """Decorator that registers a field validator."""
    def decorator(func):
        if not hasattr(func, '_validators'):
            func._validators = []
        func._validators.append({'fields': fields, 'mode': mode})
        func._is_field_validator = True
        return classmethod(func)
    return decorator


def model_validator(*, mode="after"):
    """Decorator that registers a model validator."""
    def decorator(func):
        func._is_model_validator = True
        func._validator_mode = mode
        return func
    return decorator


class _BaseModelMeta(type):
    """Metaclass that collects field validators."""
    def __new__(mcs, name, bases, namespace):
        validators = {}
        for attr_name, attr_value in namespace.items():
            func = attr_value
            if isinstance(func, classmethod):
                func = func.__func__
            if callable(func) and getattr(func, '_is_field_validator', False):
                for info in func._validators:
                    for field_name in info['fields']:
                        if field_name not in validators:
                            validators[field_name] = []
                        validators[field_name].append({
                            'func': func,
                            'mode': info['mode'],
                        })
        
        cls = super().__new__(mcs, name, bases, namespace)
        cls.__field_validators__ = validators
        return cls


class BaseModel(metaclass=_BaseModelMeta):
    """Minimal BaseModel implementation."""
    
    model_config: ClassVar[ConfigDict] = ConfigDict()
    __field_validators__: ClassVar[dict] = {}
    
    def __init__(self, **kwargs):
        hints = {}
        for klass in reversed(type(self).__mro__):
            if klass is object:
                continue
            try:
                hints.update(get_type_hints(klass))
            except Exception:
                pass
        
        # Get class-level defaults
        for name in hints:
            if name.startswith('_') or name == 'model_config':
                continue
            
            # Check for alias in Field definitions
            class_default = getattr(type(self), name, ...)
            
            if isinstance(class_default, FieldInfo):
                alias = class_default.alias
                if alias and alias in kwargs:
                    value = kwargs[alias]
                elif name in kwargs:
                    value = kwargs[name]
                elif class_default.default is not ...:
                    value = class_default.default
                else:
                    value = None
            elif name in kwargs:
                value = kwargs[name]
            elif class_default is not ...:
                value = class_default
            else:
                value = None
            
            # Run "before" validators
            if name in self.__field_validators__:
                for v in self.__field_validators__[name]:
                    if v['mode'] == 'before':
                        try:
                            value = v['func'](value)
                        except TypeError:
                            value = v['func'](type(self), value)
            
            # Basic type coercion for nested models
            value = self._coerce_value(hints.get(name), value)
            
            setattr(self, name, value)
            
            # Run "after" validators
            if name in self.__field_validators__:
                for v in self.__field_validators__[name]:
                    if v['mode'] == 'after':
                        try:
                            result = v['func'](getattr(self, name))
                        except TypeError:
                            result = v['func'](type(self), getattr(self, name))
                        if result is not None:
                            setattr(self, name, result)
        
        # Also set any extra kwargs not in hints (for flexibility)
        for name, value in kwargs.items():
            if not hasattr(self, name) and not name.startswith('_'):
                setattr(self, name, value)
        
        self.model_post_init(None)
    
    def _coerce_value(self, type_hint, value):
        """Attempt to coerce value to the expected type."""
        if value is None or type_hint is None:
            return value
        
        import typing
        from datetime import datetime
        from pathlib import Path
        
        origin = getattr(type_hint, '__origin__', None)
        args = getattr(type_hint, '__args__', ())
        
        # Handle Optional[X] = Union[X, None]
        if origin is type(None):
            return value
        
        # Handle list[X]
        if origin is list and args and isinstance(value, list):
            item_type = args[0]
            if isinstance(item_type, type) and issubclass(item_type, BaseModel):
                return [
                    item_type.model_validate(item) if isinstance(item, dict) else item
                    for item in value
                ]
            return value
        
        # Handle Union types (including Optional)
        if origin is getattr(typing, 'Union', None):
            for arg in args:
                if arg is type(None):
                    continue
                if isinstance(arg, type) and issubclass(arg, BaseModel) and isinstance(value, dict):
                    try:
                        return arg.model_validate(value)
                    except Exception:
                        continue
                # Coerce to datetime
                if arg is datetime and isinstance(value, str):
                    try:
                        return datetime.fromisoformat(value.replace('Z', '+00:00'))
                    except (ValueError, TypeError):
                        pass
                # Coerce to Path
                if arg is Path and isinstance(value, str):
                    return Path(value)
            return value
        
        # Handle nested BaseModel
        if isinstance(type_hint, type) and issubclass(type_hint, BaseModel) and isinstance(value, dict):
            return type_hint.model_validate(value)
        
        # Handle datetime
        if type_hint is datetime and isinstance(value, str):
            try:
                return datetime.fromisoformat(value.replace('Z', '+00:00'))
            except (ValueError, TypeError):
                return value
        
        # Handle Path
        if type_hint is Path and isinstance(value, str):
            return Path(value)
        
        return value
    
    def model_post_init(self, __context):
        """Override in subclass for post-init logic."""
        pass
    
    @classmethod
    def model_validate(cls, obj, **kwargs):
        """Create instance from dict or existing instance."""
        if isinstance(obj, cls):
            return obj
        if isinstance(obj, dict):
            return cls(**obj)
        raise ValueError(f"Cannot validate {type(obj)} as {cls.__name__}")
    
    @classmethod
    def model_validate_json(cls, json_data, **kwargs):
        """Create instance from JSON string."""
        if isinstance(json_data, (bytes, bytearray)):
            json_data = json_data.decode('utf-8')
        data = json.loads(json_data)
        return cls.model_validate(data)
    
    def model_dump(self, **kwargs):
        """Serialize to dict."""
        result = {}
        hints = get_type_hints(type(self))
        for name in hints:
            if name.startswith('_') or name == 'model_config':
                continue
            value = getattr(self, name, None)
            if isinstance(value, BaseModel):
                value = value.model_dump(**kwargs)
            elif isinstance(value, list):
                value = [
                    item.model_dump(**kwargs) if isinstance(item, BaseModel) else item
                    for item in value
                ]
            result[name] = value
        return result
    
    def model_dump_json(self, **kwargs):
        """Serialize to JSON string."""
        return json.dumps(self.model_dump(**kwargs))
    
    def __repr__(self):
        hints = get_type_hints(type(self))
        fields = []
        for name in hints:
            if name.startswith('_') or name == 'model_config':
                continue
            fields.append(f"{name}={getattr(self, name, None)!r}")
        return f"{type(self).__name__}({', '.join(fields)})"
    
    def __eq__(self, other):
        if type(self) is not type(other):
            return False
        hints = get_type_hints(type(self))
        for name in hints:
            if name.startswith('_') or name == 'model_config':
                continue
            if getattr(self, name, None) != getattr(other, name, None):
                return False
        return True
