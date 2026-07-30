import { a as require_react, i as useRouter, o as __toESM, r as usePathname, t as require_jsx_runtime } from "../index.js";
//#region node_modules/vinext/dist/utils/navigation-signal.js
function getErrorDigest(error) {
	if (!error || typeof error !== "object" || !("digest" in error)) return null;
	return String(error.digest);
}
function isNavigationSignalError(error) {
	const digest = getErrorDigest(error);
	if (digest === null) return false;
	return digest === "NEXT_NOT_FOUND" || digest.startsWith("NEXT_HTTP_ERROR_FALLBACK;") || digest.startsWith("NEXT_REDIRECT;");
}
//#endregion
//#region node_modules/vinext/dist/shims/error-boundary.js
var import_react = /* @__PURE__ */ __toESM(require_react(), 1);
var import_jsx_runtime = require_jsx_runtime();
function normalizeBoundaryResetKey(resetKey) {
	return resetKey === void 0 || resetKey === null || resetKey === "" ? null : resetKey;
}
function readBoundaryResetState(props) {
	return {
		previousPathname: props.pathname,
		previousResetKey: normalizeBoundaryResetKey(props.resetKey)
	};
}
function shouldResetBoundary(nextResetState, previousResetState) {
	const nextResetKey = normalizeBoundaryResetKey(nextResetState.previousResetKey);
	const previousResetKey = normalizeBoundaryResetKey(previousResetState.previousResetKey);
	if (nextResetKey !== null || previousResetKey !== null) return nextResetKey !== previousResetKey;
	return nextResetState.previousPathname !== previousResetState.previousPathname;
}
function isRedirectError(error) {
	return getErrorDigest(error)?.startsWith("NEXT_REDIRECT;") ?? false;
}
function decodeRedirectTarget(target) {
	try {
		return decodeURIComponent(target);
	} catch {
		return target;
	}
}
function getURLFromRedirectError(error) {
	const parts = error.digest.split(";");
	const encodedTarget = parts.length >= 5 ? parts.slice(2, -2).join(";") : parts[2];
	return encodedTarget ? decodeRedirectTarget(encodedTarget) : null;
}
function getRedirectTypeFromError(error) {
	return error.digest.split(";", 2)[1] === "push" ? "push" : "replace";
}
function HandleRedirect({ redirect, redirectType }) {
	const router = useRouter();
	import_react.useEffect(() => {
		import_react.startTransition(() => {
			if (redirectType === "push") router.push(redirect);
			else router.replace(redirect);
		});
	}, [
		redirect,
		redirectType,
		router
	]);
	return null;
}
var RedirectErrorBoundary = class extends import_react.Component {
	constructor(props) {
		super(props);
		this.state = {
			redirect: null,
			redirectType: null
		};
	}
	static getDerivedStateFromError(error) {
		if (isRedirectError(error)) {
			if (error.handled) return {
				redirect: null,
				redirectType: null
			};
			const url = getURLFromRedirectError(error);
			if (url === null) throw error;
			return {
				redirect: url,
				redirectType: getRedirectTypeFromError(error)
			};
		}
		throw error;
	}
	render() {
		const { redirect, redirectType } = this.state;
		if (redirect !== null && redirectType !== null) return /* @__PURE__ */ (0, import_jsx_runtime.jsx)(HandleRedirect, {
			redirect,
			redirectType
		});
		return this.props.children;
	}
};
function RedirectBoundary({ children }) {
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)(RedirectErrorBoundary, { children });
}
/**
* Generic ErrorBoundary used to wrap route segments with error.tsx.
* This must be a client component since error boundaries use
* componentDidCatch / getDerivedStateFromError.
*/
var ErrorBoundaryInner = class extends import_react.Component {
	constructor(props) {
		super(props);
		this.state = {
			error: null,
			...readBoundaryResetState(props)
		};
	}
	static getDerivedStateFromProps(props, state) {
		const nextResetState = readBoundaryResetState(props);
		if (state.error && shouldResetBoundary(nextResetState, state)) return {
			error: null,
			...nextResetState
		};
		return {
			error: state.error,
			...nextResetState
		};
	}
	static getDerivedStateFromError(error) {
		if (isNavigationSignalError(error)) throw error;
		return { error: { thrownValue: error } };
	}
	reset = () => {
		this.setState({ error: null });
	};
	render() {
		if (this.state.error) {
			const FallbackComponent = this.props.fallback;
			return /* @__PURE__ */ (0, import_jsx_runtime.jsx)(FallbackComponent, {
				error: this.state.error.thrownValue,
				reset: this.reset
			});
		}
		return this.props.children;
	}
};
function ErrorBoundary({ fallback, children, resetKey }) {
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)(ErrorBoundaryInner, {
		pathname: usePathname(),
		resetKey,
		fallback,
		children
	});
}
/**
* Inner class component that catches notFound() errors and renders the
* not-found.tsx fallback. Resets on the caller's segment reset key when one is
* provided, otherwise falls back to pathname changes for legacy callers.
*
* The ErrorBoundary above re-throws notFound errors so they propagate up to this
* boundary. This must be placed above the ErrorBoundary in the component tree.
*/
var NotFoundBoundaryInner = class extends import_react.Component {
	constructor(props) {
		super(props);
		this.state = {
			notFound: false,
			...readBoundaryResetState(props)
		};
	}
	static getDerivedStateFromProps(props, state) {
		const nextResetState = readBoundaryResetState(props);
		if (state.notFound && shouldResetBoundary(nextResetState, state)) return {
			notFound: false,
			...nextResetState
		};
		return {
			notFound: state.notFound,
			...nextResetState
		};
	}
	static getDerivedStateFromError(error) {
		if (error && typeof error === "object" && "digest" in error) {
			const digest = String(error.digest);
			if (digest === "NEXT_NOT_FOUND" || digest === "NEXT_HTTP_ERROR_FALLBACK;404") return { notFound: true };
		}
		throw error;
	}
	render() {
		if (this.state.notFound) return this.props.fallback;
		return this.props.children;
	}
};
/**
* Wrapper that reads the current pathname and passes it to the inner class
* component. Segment reset keys own App Router remount semantics when present.
*/
function NotFoundBoundary({ fallback, children, resetKey }) {
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)(NotFoundBoundaryInner, {
		pathname: usePathname(),
		resetKey,
		fallback,
		children
	});
}
var ForbiddenBoundaryInner = class extends import_react.Component {
	constructor(props) {
		super(props);
		this.state = {
			forbidden: false,
			...readBoundaryResetState(props)
		};
	}
	static getDerivedStateFromProps(props, state) {
		const nextResetState = readBoundaryResetState(props);
		if (state.forbidden && shouldResetBoundary(nextResetState, state)) return {
			forbidden: false,
			...nextResetState
		};
		return {
			forbidden: state.forbidden,
			...nextResetState
		};
	}
	static getDerivedStateFromError(error) {
		if (error && typeof error === "object" && "digest" in error) {
			if (String(error.digest) === "NEXT_HTTP_ERROR_FALLBACK;403") return { forbidden: true };
		}
		throw error;
	}
	render() {
		if (this.state.forbidden) return this.props.fallback;
		return this.props.children;
	}
};
function ForbiddenBoundary({ fallback, children, resetKey }) {
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)(ForbiddenBoundaryInner, {
		pathname: usePathname(),
		resetKey,
		fallback,
		children
	});
}
var UnauthorizedBoundaryInner = class extends import_react.Component {
	constructor(props) {
		super(props);
		this.state = {
			unauthorized: false,
			...readBoundaryResetState(props)
		};
	}
	static getDerivedStateFromProps(props, state) {
		const nextResetState = readBoundaryResetState(props);
		if (state.unauthorized && shouldResetBoundary(nextResetState, state)) return {
			unauthorized: false,
			...nextResetState
		};
		return {
			unauthorized: state.unauthorized,
			...nextResetState
		};
	}
	static getDerivedStateFromError(error) {
		if (error && typeof error === "object" && "digest" in error) {
			if (String(error.digest) === "NEXT_HTTP_ERROR_FALLBACK;401") return { unauthorized: true };
		}
		throw error;
	}
	render() {
		if (this.state.unauthorized) return this.props.fallback;
		return this.props.children;
	}
};
function UnauthorizedBoundary({ fallback, children, resetKey }) {
	return /* @__PURE__ */ (0, import_jsx_runtime.jsx)(UnauthorizedBoundaryInner, {
		pathname: usePathname(),
		resetKey,
		fallback,
		children
	});
}
import_react.Component;
//#endregion
export { ErrorBoundary, ForbiddenBoundary, NotFoundBoundary, RedirectBoundary, UnauthorizedBoundary };
