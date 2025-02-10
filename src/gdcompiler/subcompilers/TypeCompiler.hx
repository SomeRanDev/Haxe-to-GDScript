package gdcompiler.subcompilers;

import gdcompiler.config.Meta;
import gdcompiler.GDCompiler;

import reflaxe.helpers.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.TypeTools;

using reflaxe.helpers.ArrayHelper;
using reflaxe.helpers.BaseTypeHelper;
using reflaxe.helpers.ModuleTypeHelper;
using reflaxe.helpers.NameMetaHelper;
using reflaxe.helpers.NullableMetaAccessHelper;
using reflaxe.helpers.TypeHelper;

@:access(gdcompiler.GDCompiler)
class TypeCompiler {
	var main: GDCompiler;

	public function new(main: GDCompiler) {
		this.main = main;
	}

	public function compileClassName(classType: ClassType): String {
		return classType.getNameOrNativeName();
	}

	function compileModuleType(m: ModuleType, isExport: Bool): String {
		return switch(m) {
			case TClassDecl(clsRef): {
				compileClassName(clsRef.get());
			}
			case TEnumDecl(enmRef): {
				compileEnum(enmRef, isExport);
			}
			case _: m.getNameOrNative();
		}
	}

	function compileEnum(enmRef: Ref<EnumType>, isExport: Bool) {
		final e = enmRef.get();
		return if(e.isReflaxeExtern()) {
			e.pack.joinAppend(".") + e.getNameOrNativeName();
		} else if(!isExport) {
			"Variant";
		} else {
			"Dictionary";
		}
	}

	public function compileType(t: Type, errorPos: Position, isExport: Bool = false): Null<String> {
		// Check for @:dont_compile
		if(t.getMeta().maybeHas(Meta.DontCompile)) {
			return null;
		}

		// Process and return content from @:nativeTypeCode
		if(t.getMeta().maybeHas(":nativeTypeCode")) {
			final params = t.getParams();
			final paramCallbacks = if(params != null && params.length > 0) {
				params.map(paramType -> (() -> compileType(paramType, errorPos, isExport) ?? "Variant"));
			} else {
				[];
			}
			final code = main.compileNativeTypeCodeMeta(t, paramCallbacks);
			if(code != null) {
				return code;
			}
		}

		if(t.isNull()) {
			return null;
		}
		// Ignore Null<T> and just compile as T
		// if(t.isNull()) {
		// 	switch(Context.follow(t.unwrapNullTypeOrSelf())) {
		// 		case TEnum(_, _) | TAnonymous(_) if(!isExport): return "Variant";
		// 		case _:
		// 	}
		// 	return compileType(t.unwrapNullTypeOrSelf(), errorPos, isExport);
		// }

		switch(t) {
			case TAbstract(absRef, params): {
				final abs = absRef.get();

				final primitiveResult = if(params.length == 0) {
					switch(abs.name) {
						case "Void": "void";
						case "Int": "int";
						case "Float":"float";
						case "Single": "float";
						case "Bool": "bool";
						case "Any" | "Dynamic": null;
						case _: null;
					}
				} else {
					null;
				}

				if(primitiveResult != null) {
					return primitiveResult;
				}

				// Compile internal type for Abstract
				final absType = abs.type;

				// Apply type parameters to figure out internal type.
				final internalType = #if macro {
					TypeTools.applyTypeParameters(absType, abs.params, params);
				} #else absType #end;

				// If Null<T>, must be Variant since built-in types cannot be assigned `null`.
				if(internalType.isNull()) {
					return null;
				}

				// Prevent recursion...
				if(!internalType.equals(t)) {
					return compileType(internalType, errorPos, isExport);
				}
			}

			case TDynamic(_): return null;
			case TAnonymous(_): return "Dictionary";
			case TFun(_, _): return null;
			case _ if(t.isTypeParameter()): return null;

			case TInst(clsRef, _): {
				return compileModuleType(TClassDecl(clsRef), isExport);
			}
			case TEnum(enmRef, _): return compileEnum(enmRef, isExport);
			case TType(defRef, _): return compileType(defRef.get().type, errorPos, isExport);

			case TMono(typeRef): {
				final t = typeRef.get();
				return if(t != null) compileType(t, errorPos, isExport);
				else null; // It's okay to return `null` here.
			}

			case _:
		}

		// Old behavior
		// TODO: Phase this out...
		final ct = haxe.macro.TypeTools.toComplexType(t);
		final typeName = switch(ct) {
			case TPath(typePath): {
				// copy TypePath and ignore "params" since GDScript is typeless
				haxe.macro.ComplexTypeTools.toString(TPath({
					name: typePath.name,
					pack: typePath.pack,
					sub: typePath.sub,
					params: null
				}));
			}
			case _: null;
		}
		if(typeName == null) {
			return Context.error("Incomplete Feature: Cannot convert this type to GDScript at the moment. " + Std.string(t), errorPos);
		}
		return typeName;
	}
}
