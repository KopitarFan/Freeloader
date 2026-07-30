import { a as require_react, n as getLayoutSegmentContext, o as __toESM } from "../index.js";
//#region node_modules/vinext/dist/shims/layout-segment-context.js
var import_react = /* @__PURE__ */ __toESM(require_react(), 1);
/**
* Layout segment context provider.
*
* Must be "use client" so that Vite's RSC bundler renders this component in
* the SSR/browser environment where React.createContext is available. The RSC
* entry imports and renders LayoutSegmentProvider directly, but because of the
* "use client" boundary the actual execution happens on the SSR/client side
* where the context can be created and consumed by useSelectedLayoutSegment(s).
*
* Without "use client", this runs in the RSC environment where
* React.createContext is undefined, getLayoutSegmentContext() returns null,
* the provider becomes a no-op, and useSelectedLayoutSegments always returns [].
*
* The context is shared with navigation.ts via getLayoutSegmentContext()
* to avoid creating separate contexts in different modules.
*/
/**
* Wraps children with the layout segment context.
*
* Each layout in the App Router tree wraps its children with this provider,
* passing a map of parallel route key to segment path. The "children" key is
* always present (the default parallel route). Named parallel slots at this
* layout level add their own keys.
*
* Components inside the provider call useSelectedLayoutSegments(parallelRoutesKey)
* to read the segments for a specific parallel route.
*/
function LayoutSegmentProvider({ segmentMap, children }) {
	const ctx = getLayoutSegmentContext();
	if (!ctx) return children;
	return (0, import_react.createElement)(ctx.Provider, { value: segmentMap }, children);
}
//#endregion
export { LayoutSegmentProvider };
