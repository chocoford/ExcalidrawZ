#if os(macOS)
import Foundation
import WebKit

@MainActor
enum ScreenAnnotationElementPropertiesBridge {
    static func apply(
        _ changes: ElementProperties,
        to elementIDs: [String],
        boundTextElementIDs: [String],
        in webView: WKWebView
    ) async throws {
        guard let propertiesJSON = changes.toJSONString(),
              let elementIDsData = try? JSONEncoder().encode(elementIDs),
              let elementIDsJSON = String(
                data: elementIDsData,
                encoding: .utf8
              ),
              let boundTextIDsData = try? JSONEncoder().encode(
                boundTextElementIDs
              ),
              let boundTextIDsJSON = String(
                data: boundTextIDsData,
                encoding: .utf8
              ) else {
            return
        }

        _ = try await webView.callAsyncJavaScript(
            """
            const helper = window.excalidrawZHelper;
            const properties = JSON.parse(propertiesJSON);
            const ids = JSON.parse(elementIDsJSON);
            const boundTextIds = JSON.parse(boundTextIDsJSON);
            const has = (key) =>
              Object.prototype.hasOwnProperty.call(properties, key);
            if (has("arrowType")) {
              if (typeof helper?.setArrowType !== "function") {
                throw new Error(
                  "Excalidraw helper setArrowType API is unavailable."
                );
              }
              helper.setArrowType(ids, properties.arrowType, {
                captureUpdate: "IMMEDIATELY",
              });
            }
            const selectedElements = helper?.getElementsByIds?.(ids) ?? [];
            const boundTextElements =
              helper?.getElementsByIds?.(boundTextIds) ?? [];
            const elements = [...selectedElements, ...boundTextElements];
            const boundTextIdSet = new Set(boundTextIds);
            const currentItemUpdates = {};
            const strokeWidths = {
              thin: { regular: 1, freedraw: 0.5 },
              medium: { regular: 2, freedraw: 1 },
              bold: { regular: 4, freedraw: 2 },
            };

            const currentItemPropertyKeys = {
              strokeColor: "currentItemStrokeColor",
              backgroundColor: "currentItemBackgroundColor",
              fillStyle: "currentItemFillStyle",
              strokeWidthKey: "currentItemStrokeWidthKey",
              strokeVariability: "currentItemStrokeVariability",
              strokeStyle: "currentItemStrokeStyle",
              roughness: "currentItemRoughness",
              opacity: "currentItemOpacity",
              fontFamily: "currentItemFontFamily",
              fontSize: "currentItemFontSize",
              textAlign: "currentItemTextAlign",
              roundness: "currentItemRoundness",
              arrowType: "currentItemArrowType",
              startArrowhead: "currentItemStartArrowhead",
              endArrowhead: "currentItemEndArrowhead",
            };
            for (const [propertyKey, appStateKey] of Object.entries(
              currentItemPropertyKeys
            )) {
              if (has(propertyKey)) {
                currentItemUpdates[appStateKey] = properties[propertyKey];
              }
            }

            const patches = elements.map((element) => {
              const updates = {};
              const isBoundText = boundTextIdSet.has(element.id);
              if (!isBoundText) {
                if (has("strokeColor")) {
                  updates.strokeColor = properties.strokeColor;
                }
                if (has("backgroundColor")) {
                  updates.backgroundColor = properties.backgroundColor;
                }
                if (has("fillStyle")) {
                  updates.fillStyle = properties.fillStyle;
                }
                if (has("strokeStyle")) {
                  updates.strokeStyle = properties.strokeStyle;
                }
                if (has("roughness")) {
                  updates.roughness = properties.roughness;
                }
                if (has("opacity")) {
                  updates.opacity = properties.opacity;
                }
                if (has("strokeWidthKey")) {
                  const widths = strokeWidths[properties.strokeWidthKey];
                  if (widths) {
                    updates.strokeWidth =
                      element.type === "freedraw"
                        ? widths.freedraw
                        : widths.regular;
                  }
                }
                if (
                  element.type === "freedraw" &&
                  has("strokeVariability")
                ) {
                  updates.strokeOptions = {
                    ...(element.strokeOptions ?? {}),
                    variability: properties.strokeVariability,
                  };
                }
              }
              if (element.type === "text") {
                if (has("fontFamily")) {
                  updates.fontFamily = properties.fontFamily;
                }
                if (has("fontSize")) {
                  updates.fontSize = properties.fontSize;
                }
                if (has("textAlign")) {
                  updates.textAlign = properties.textAlign;
                }
              }
              if (
                has("roundness") &&
                element.type !== "freedraw" &&
                element.type !== "text"
              ) {
                updates.roundness =
                  properties.roundness === "round"
                    ? { type: element.type === "rectangle" ? 3 : 2 }
                    : null;
              }
              if (element.type === "arrow") {
                if (has("startArrowhead")) {
                  updates.startArrowhead = properties.startArrowhead;
                }
                if (has("endArrowhead")) {
                  updates.endArrowhead = properties.endArrowhead;
                }
              }
              return Object.keys(updates).length > 0
                ? { id: element.id, updates }
                : null;
            }).filter(Boolean);

            if (patches.length > 0) {
              helper?.updateElements?.(patches, {
                captureUpdate: "IMMEDIATELY",
              });
            }
            if (Object.keys(currentItemUpdates).length > 0) {
              const api = helper?._api;
              if (typeof api?.updateScene !== "function") {
                throw new Error(
                  "Excalidraw API for current item properties is unavailable."
                );
              }
              api.updateScene({
                appState: currentItemUpdates,
                captureUpdate: "NEVER",
              });
            }
            """,
            arguments: [
                "propertiesJSON": propertiesJSON,
                "elementIDsJSON": elementIDsJSON,
                "boundTextIDsJSON": boundTextIDsJSON,
            ],
            contentWorld: .page
        )
    }
}
#endif
