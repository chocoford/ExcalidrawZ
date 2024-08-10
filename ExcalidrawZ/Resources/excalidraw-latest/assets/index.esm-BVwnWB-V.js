import{_ as Y,a as z,b as x,c as S,d as J,e as K,f as $}from"./index-DDDkAZj4.js";/**
 * @license
 * Copyright 2017 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */function X(t){return C(void 0,t)}function C(t,e){if(!(e instanceof Object))return e;switch(e.constructor){case Date:var r=e;return new Date(r.getTime());case Object:t===void 0&&(t={});break;case Array:t=[];break;default:return e}for(var n in e)!e.hasOwnProperty(n)||!Z(n)||(t[n]=C(t[n],e[n]));return t}function Z(t){return t!=="__proto__"}/**
 * @license
 * Copyright 2017 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var q=function(){function t(){var e=this;this.reject=function(){},this.resolve=function(){},this.promise=new Promise(function(r,n){e.resolve=r,e.reject=n})}return t.prototype.wrapCallback=function(e){var r=this;return function(n,o){n?r.reject(n):r.resolve(o),typeof e=="function"&&(r.promise.catch(function(){}),e.length===1?e(n):e(n,o))}},t}();/**
 * @license
 * Copyright 2017 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */function F(){return typeof navigator<"u"&&typeof navigator.userAgent=="string"?navigator.userAgent:""}function $e(){return typeof window<"u"&&!!(window.cordova||window.phonegap||window.PhoneGap)&&/ios|iphone|ipod|ipad|android|blackberry|iemobile/i.test(F())}function Q(){try{return Object.prototype.toString.call(global.process)==="[object process]"}catch{return!1}}function ee(){return typeof self=="object"&&self.self===self}function ke(){var t=typeof chrome=="object"?chrome.runtime:typeof browser=="object"?browser.runtime:void 0;return typeof t=="object"&&t.id!==void 0}function Be(){return typeof navigator=="object"&&navigator.product==="ReactNative"}function Ue(){return F().indexOf("Electron/")>=0}function Ve(){var t=F();return t.indexOf("MSIE ")>=0||t.indexOf("Trident/")>=0}function We(){return F().indexOf("MSAppHost/")>=0}/**
 * @license
 * Copyright 2017 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var te="FirebaseError",re=function(t){Y(e,t);function e(r,n,o){var i=t.call(this,n)||this;return i.code=r,i.customData=o,i.name=te,Object.setPrototypeOf(i,e.prototype),Error.captureStackTrace&&Error.captureStackTrace(i,T.prototype.create),i}return e}(Error),T=function(){function t(e,r,n){this.service=e,this.serviceName=r,this.errors=n}return t.prototype.create=function(e){for(var r=[],n=1;n<arguments.length;n++)r[n-1]=arguments[n];var o=r[0]||{},i=this.service+"/"+e,f=this.errors[e],p=f?ne(f,o):"Error",d=this.serviceName+": "+p+" ("+i+").",y=new re(i,d,o);return y},t}();function ne(t,e){return t.replace(ie,function(r,n){var o=e[n];return o!=null?String(o):"<"+n+"?>"})}var ie=/\{\$([^}]+)}/g;/**
 * @license
 * Copyright 2017 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */function k(t,e){return Object.prototype.hasOwnProperty.call(t,e)}function oe(t,e){var r=new ae(t,e);return r.subscribe.bind(r)}var ae=function(){function t(e,r){var n=this;this.observers=[],this.unsubscribes=[],this.observerCount=0,this.task=Promise.resolve(),this.finalized=!1,this.onNoObservers=r,this.task.then(function(){e(n)}).catch(function(o){n.error(o)})}return t.prototype.next=function(e){this.forEachObserver(function(r){r.next(e)})},t.prototype.error=function(e){this.forEachObserver(function(r){r.error(e)}),this.close(e)},t.prototype.complete=function(){this.forEachObserver(function(e){e.complete()}),this.close()},t.prototype.subscribe=function(e,r,n){var o=this,i;if(e===void 0&&r===void 0&&n===void 0)throw new Error("Missing Observer.");se(e,["next","error","complete"])?i=e:i={next:e,error:r,complete:n},i.next===void 0&&(i.next=D),i.error===void 0&&(i.error=D),i.complete===void 0&&(i.complete=D);var f=this.unsubscribeOne.bind(this,this.observers.length);return this.finalized&&this.task.then(function(){try{o.finalError?i.error(o.finalError):i.complete()}catch{}}),this.observers.push(i),f},t.prototype.unsubscribeOne=function(e){this.observers===void 0||this.observers[e]===void 0||(delete this.observers[e],this.observerCount-=1,this.observerCount===0&&this.onNoObservers!==void 0&&this.onNoObservers(this))},t.prototype.forEachObserver=function(e){if(!this.finalized)for(var r=0;r<this.observers.length;r++)this.sendOne(r,e)},t.prototype.sendOne=function(e,r){var n=this;this.task.then(function(){if(n.observers!==void 0&&n.observers[e]!==void 0)try{r(n.observers[e])}catch(o){typeof console<"u"&&console.error&&console.error(o)}})},t.prototype.close=function(e){var r=this;this.finalized||(this.finalized=!0,e!==void 0&&(this.finalError=e),this.task.then(function(){r.observers=void 0,r.onNoObservers=void 0}))},t}();function se(t,e){if(typeof t!="object"||t===null)return!1;for(var r=0,n=e;r<n.length;r++){var o=n[r];if(o in t&&typeof t[o]=="function")return!0}return!1}function D(){}/**
 * @license
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */function Ge(t){return t&&t._delegate?t._delegate:t}var j=function(){function t(e,r,n){this.name=e,this.instanceFactory=r,this.type=n,this.multipleInstances=!1,this.serviceProps={},this.instantiationMode="LAZY",this.onInstanceCreated=null}return t.prototype.setInstantiationMode=function(e){return this.instantiationMode=e,this},t.prototype.setMultipleInstances=function(e){return this.multipleInstances=e,this},t.prototype.setServiceProps=function(e){return this.serviceProps=e,this},t.prototype.setInstanceCreatedCallback=function(e){return this.onInstanceCreated=e,this},t}();/**
 * @license
 * Copyright 2019 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var N="[DEFAULT]";/**
 * @license
 * Copyright 2019 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var ue=function(){function t(e,r){this.name=e,this.container=r,this.component=null,this.instances=new Map,this.instancesDeferred=new Map}return t.prototype.get=function(e){e===void 0&&(e=N);var r=this.normalizeInstanceIdentifier(e);if(!this.instancesDeferred.has(r)){var n=new q;if(this.instancesDeferred.set(r,n),this.isInitialized(r)||this.shouldAutoInitialize())try{var o=this.getOrInitializeService({instanceIdentifier:r});o&&n.resolve(o)}catch{}}return this.instancesDeferred.get(r).promise},t.prototype.getImmediate=function(e){var r=z({identifier:N,optional:!1},e),n=r.identifier,o=r.optional,i=this.normalizeInstanceIdentifier(n);if(this.isInitialized(i)||this.shouldAutoInitialize())try{return this.getOrInitializeService({instanceIdentifier:i})}catch(f){if(o)return null;throw f}else{if(o)return null;throw Error("Service "+this.name+" is not available")}},t.prototype.getComponent=function(){return this.component},t.prototype.setComponent=function(e){var r,n;if(e.name!==this.name)throw Error("Mismatching Component "+e.name+" for Provider "+this.name+".");if(this.component)throw Error("Component for "+this.name+" has already been provided");if(this.component=e,!!this.shouldAutoInitialize()){if(le(e))try{this.getOrInitializeService({instanceIdentifier:N})}catch{}try{for(var o=x(this.instancesDeferred.entries()),i=o.next();!i.done;i=o.next()){var f=S(i.value,2),p=f[0],d=f[1],y=this.normalizeInstanceIdentifier(p);try{var m=this.getOrInitializeService({instanceIdentifier:y});d.resolve(m)}catch{}}}catch(c){r={error:c}}finally{try{i&&!i.done&&(n=o.return)&&n.call(o)}finally{if(r)throw r.error}}}},t.prototype.clearInstance=function(e){e===void 0&&(e=N),this.instancesDeferred.delete(e),this.instances.delete(e)},t.prototype.delete=function(){return J(this,void 0,void 0,function(){var e;return K(this,function(r){switch(r.label){case 0:return e=Array.from(this.instances.values()),[4,Promise.all($($([],S(e.filter(function(n){return"INTERNAL"in n}).map(function(n){return n.INTERNAL.delete()}))),S(e.filter(function(n){return"_delete"in n}).map(function(n){return n._delete()}))))];case 1:return r.sent(),[2]}})})},t.prototype.isComponentSet=function(){return this.component!=null},t.prototype.isInitialized=function(e){return e===void 0&&(e=N),this.instances.has(e)},t.prototype.initialize=function(e){var r,n;e===void 0&&(e={});var o=e.instanceIdentifier,i=o===void 0?N:o,f=e.options,p=f===void 0?{}:f,d=this.normalizeInstanceIdentifier(i);if(this.isInitialized(d))throw Error(this.name+"("+d+") has already been initialized");if(!this.isComponentSet())throw Error("Component "+this.name+" has not been registered yet");var y=this.getOrInitializeService({instanceIdentifier:d,options:p});try{for(var m=x(this.instancesDeferred.entries()),c=m.next();!c.done;c=m.next()){var s=S(c.value,2),a=s[0],g=s[1],v=this.normalizeInstanceIdentifier(a);d===v&&g.resolve(y)}}catch(l){r={error:l}}finally{try{c&&!c.done&&(n=m.return)&&n.call(m)}finally{if(r)throw r.error}}return y},t.prototype.getOrInitializeService=function(e){var r=e.instanceIdentifier,n=e.options,o=n===void 0?{}:n,i=this.instances.get(r);if(!i&&this.component&&(i=this.component.instanceFactory(this.container,{instanceIdentifier:fe(r),options:o}),this.instances.set(r,i),this.component.onInstanceCreated))try{this.component.onInstanceCreated(this.container,r,i)}catch{}return i||null},t.prototype.normalizeInstanceIdentifier=function(e){return this.component?this.component.multipleInstances?e:N:e},t.prototype.shouldAutoInitialize=function(){return!!this.component&&this.component.instantiationMode!=="EXPLICIT"},t}();function fe(t){return t===N?void 0:t}function le(t){return t.instantiationMode==="EAGER"}/**
 * @license
 * Copyright 2019 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var ce=function(){function t(e){this.name=e,this.providers=new Map}return t.prototype.addComponent=function(e){var r=this.getProvider(e.name);if(r.isComponentSet())throw new Error("Component "+e.name+" has already been registered with "+this.name);r.setComponent(e)},t.prototype.addOrOverwriteComponent=function(e){var r=this.getProvider(e.name);r.isComponentSet()&&this.providers.delete(e.name),this.addComponent(e)},t.prototype.getProvider=function(e){if(this.providers.has(e))return this.providers.get(e);var r=new ue(e,this);return this.providers.set(e,r),r},t.prototype.getProviders=function(){return Array.from(this.providers.values())},t}();/*! *****************************************************************************
Copyright (c) Microsoft Corporation. All rights reserved.
Licensed under the Apache License, Version 2.0 (the "License"); you may not use
this file except in compliance with the License. You may obtain a copy of the
License at http://www.apache.org/licenses/LICENSE-2.0

THIS CODE IS PROVIDED ON AN *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
MERCHANTABLITY OR NON-INFRINGEMENT.

See the Apache Version 2.0 License for specific language governing permissions
and limitations under the License.
***************************************************************************** */function E(){for(var t=0,e=0,r=arguments.length;e<r;e++)t+=arguments[e].length;for(var n=Array(t),o=0,e=0;e<r;e++)for(var i=arguments[e],f=0,p=i.length;f<p;f++,o++)n[o]=i[f];return n}/**
 * @license
 * Copyright 2017 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var _,H=[],u;(function(t){t[t.DEBUG=0]="DEBUG",t[t.VERBOSE=1]="VERBOSE",t[t.INFO=2]="INFO",t[t.WARN=3]="WARN",t[t.ERROR=4]="ERROR",t[t.SILENT=5]="SILENT"})(u||(u={}));var U={debug:u.DEBUG,verbose:u.VERBOSE,info:u.INFO,warn:u.WARN,error:u.ERROR,silent:u.SILENT},pe=u.INFO,he=(_={},_[u.DEBUG]="log",_[u.VERBOSE]="log",_[u.INFO]="info",_[u.WARN]="warn",_[u.ERROR]="error",_),de=function(t,e){for(var r=[],n=2;n<arguments.length;n++)r[n-2]=arguments[n];if(!(e<t.logLevel)){var o=new Date().toISOString(),i=he[e];if(i)console[i].apply(console,E(["["+o+"]  "+t.name+":"],r));else throw new Error("Attempted to log a message with an invalid logType (value: "+e+")")}},ve=function(){function t(e){this.name=e,this._logLevel=pe,this._logHandler=de,this._userLogHandler=null,H.push(this)}return Object.defineProperty(t.prototype,"logLevel",{get:function(){return this._logLevel},set:function(e){if(!(e in u))throw new TypeError('Invalid value "'+e+'" assigned to `logLevel`');this._logLevel=e},enumerable:!1,configurable:!0}),t.prototype.setLogLevel=function(e){this._logLevel=typeof e=="string"?U[e]:e},Object.defineProperty(t.prototype,"logHandler",{get:function(){return this._logHandler},set:function(e){if(typeof e!="function")throw new TypeError("Value assigned to `logHandler` must be a function");this._logHandler=e},enumerable:!1,configurable:!0}),Object.defineProperty(t.prototype,"userLogHandler",{get:function(){return this._userLogHandler},set:function(e){this._userLogHandler=e},enumerable:!1,configurable:!0}),t.prototype.debug=function(){for(var e=[],r=0;r<arguments.length;r++)e[r]=arguments[r];this._userLogHandler&&this._userLogHandler.apply(this,E([this,u.DEBUG],e)),this._logHandler.apply(this,E([this,u.DEBUG],e))},t.prototype.log=function(){for(var e=[],r=0;r<arguments.length;r++)e[r]=arguments[r];this._userLogHandler&&this._userLogHandler.apply(this,E([this,u.VERBOSE],e)),this._logHandler.apply(this,E([this,u.VERBOSE],e))},t.prototype.info=function(){for(var e=[],r=0;r<arguments.length;r++)e[r]=arguments[r];this._userLogHandler&&this._userLogHandler.apply(this,E([this,u.INFO],e)),this._logHandler.apply(this,E([this,u.INFO],e))},t.prototype.warn=function(){for(var e=[],r=0;r<arguments.length;r++)e[r]=arguments[r];this._userLogHandler&&this._userLogHandler.apply(this,E([this,u.WARN],e)),this._logHandler.apply(this,E([this,u.WARN],e))},t.prototype.error=function(){for(var e=[],r=0;r<arguments.length;r++)e[r]=arguments[r];this._userLogHandler&&this._userLogHandler.apply(this,E([this,u.ERROR],e)),this._logHandler.apply(this,E([this,u.ERROR],e))},t}();function me(t){H.forEach(function(e){e.setLogLevel(t)})}function ge(t,e){for(var r=function(f){var p=null;e&&e.level&&(p=U[e.level]),t===null?f.userLogHandler=null:f.userLogHandler=function(d,y){for(var m=[],c=2;c<arguments.length;c++)m[c-2]=arguments[c];var s=m.map(function(a){if(a==null)return null;if(typeof a=="string")return a;if(typeof a=="number"||typeof a=="boolean")return a.toString();if(a instanceof Error)return a.message;try{return JSON.stringify(a)}catch{return null}}).filter(function(a){return a}).join(" ");y>=(p??d.logLevel)&&t({level:u[y].toLowerCase(),message:s,args:m,type:d.name})}},n=0,o=H;n<o.length;n++){var i=o[n];r(i)}}/**
 * @license
 * Copyright 2019 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var O,ye=(O={},O["no-app"]="No Firebase App '{$appName}' has been created - call Firebase App.initializeApp()",O["bad-app-name"]="Illegal App name: '{$appName}",O["duplicate-app"]="Firebase App named '{$appName}' already exists",O["app-deleted"]="Firebase App named '{$appName}' already deleted",O["invalid-app-argument"]="firebase.{$appName}() takes either no argument or a Firebase App instance.",O["invalid-log-argument"]="First argument to `onLog` must be null or a function.",O),R=new T("app","Firebase",ye),V="@firebase/app",be="0.6.19",Ee="@firebase/analytics",Ie="@firebase/auth",we="@firebase/database",Oe="@firebase/functions",Ne="@firebase/installations",_e="@firebase/messaging",Re="@firebase/performance",Ae="@firebase/remote-config",Ce="@firebase/storage",Se="@firebase/firestore",Le="firebase-wrapper";/**
 * @license
 * Copyright 2019 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var h,P="[DEFAULT]",Pe=(h={},h[V]="fire-core",h[Ee]="fire-analytics",h[Ie]="fire-auth",h[we]="fire-rtdb",h[Oe]="fire-fn",h[Ne]="fire-iid",h[_e]="fire-fcm",h[Re]="fire-perf",h[Ae]="fire-rc",h[Ce]="fire-gcs",h[Se]="fire-fst",h["fire-js"]="fire-js",h[Le]="fire-js-all",h);/**
 * @license
 * Copyright 2019 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var A=new ve("@firebase/app");/**
 * @license
 * Copyright 2017 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var L=function(){function t(e,r,n){var o=this;this.firebase_=n,this.isDeleted_=!1,this.name_=r.name,this.automaticDataCollectionEnabled_=r.automaticDataCollectionEnabled||!1,this.options_=X(e),this.container=new ce(r.name),this._addComponent(new j("app",function(){return o},"PUBLIC")),this.firebase_.INTERNAL.components.forEach(function(i){return o._addComponent(i)})}return Object.defineProperty(t.prototype,"automaticDataCollectionEnabled",{get:function(){return this.checkDestroyed_(),this.automaticDataCollectionEnabled_},set:function(e){this.checkDestroyed_(),this.automaticDataCollectionEnabled_=e},enumerable:!1,configurable:!0}),Object.defineProperty(t.prototype,"name",{get:function(){return this.checkDestroyed_(),this.name_},enumerable:!1,configurable:!0}),Object.defineProperty(t.prototype,"options",{get:function(){return this.checkDestroyed_(),this.options_},enumerable:!1,configurable:!0}),t.prototype.delete=function(){var e=this;return new Promise(function(r){e.checkDestroyed_(),r()}).then(function(){return e.firebase_.INTERNAL.removeApp(e.name_),Promise.all(e.container.getProviders().map(function(r){return r.delete()}))}).then(function(){e.isDeleted_=!0})},t.prototype._getService=function(e,r){return r===void 0&&(r=P),this.checkDestroyed_(),this.container.getProvider(e).getImmediate({identifier:r})},t.prototype._removeServiceInstance=function(e,r){r===void 0&&(r=P),this.container.getProvider(e).clearInstance(r)},t.prototype._addComponent=function(e){try{this.container.addComponent(e)}catch(r){A.debug("Component "+e.name+" failed to register with FirebaseApp "+this.name,r)}},t.prototype._addOrOverwriteComponent=function(e){this.container.addOrOverwriteComponent(e)},t.prototype.toJSON=function(){return{name:this.name,automaticDataCollectionEnabled:this.automaticDataCollectionEnabled,options:this.options}},t.prototype.checkDestroyed_=function(){if(this.isDeleted_)throw R.create("app-deleted",{appName:this.name_})},t}();L.prototype.name&&L.prototype.options||L.prototype.delete||console.log("dc");var Fe="8.3.3";/**
 * @license
 * Copyright 2019 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */function De(t){var e={},r=new Map,n={__esModule:!0,initializeApp:f,app:i,registerVersion:y,setLogLevel:me,onLog:m,apps:null,SDK_VERSION:Fe,INTERNAL:{registerComponent:d,removeApp:o,components:r,useAsService:c}};n.default=n,Object.defineProperty(n,"apps",{get:p});function o(s){delete e[s]}function i(s){if(s=s||P,!k(e,s))throw R.create("no-app",{appName:s});return e[s]}i.App=t;function f(s,a){if(a===void 0&&(a={}),typeof a!="object"||a===null){var g=a;a={name:g}}var v=a;v.name===void 0&&(v.name=P);var l=v.name;if(typeof l!="string"||!l)throw R.create("bad-app-name",{appName:String(l)});if(k(e,l))throw R.create("duplicate-app",{appName:l});var w=new t(s,v,n);return e[l]=w,w}function p(){return Object.keys(e).map(function(s){return e[s]})}function d(s){var a=s.name;if(r.has(a))return A.debug("There were multiple attempts to register component "+a+"."),s.type==="PUBLIC"?n[a]:null;if(r.set(a,s),s.type==="PUBLIC"){var g=function(b){if(b===void 0&&(b=i()),typeof b[a]!="function")throw R.create("invalid-app-argument",{appName:a});return b[a]()};s.serviceProps!==void 0&&C(g,s.serviceProps),n[a]=g,t.prototype[a]=function(){for(var b=[],I=0;I<arguments.length;I++)b[I]=arguments[I];var G=this._getService.bind(this,a);return G.apply(this,s.multipleInstances?b:[])}}for(var v=0,l=Object.keys(e);v<l.length;v++){var w=l[v];e[w]._addComponent(s)}return s.type==="PUBLIC"?n[a]:null}function y(s,a,g){var v,l=(v=Pe[s])!==null&&v!==void 0?v:s;g&&(l+="-"+g);var w=l.match(/\s|\//),b=a.match(/\s|\//);if(w||b){var I=['Unable to register library "'+l+'" with version "'+a+'":'];w&&I.push('library name "'+l+'" contains illegal characters (whitespace or "/")'),w&&b&&I.push("and"),b&&I.push('version name "'+a+'" contains illegal characters (whitespace or "/")'),A.warn(I.join(" "));return}d(new j(l+"-version",function(){return{library:l,version:a}},"VERSION"))}function m(s,a){if(s!==null&&typeof s!="function")throw R.create("invalid-log-argument");ge(s,a)}function c(s,a){if(a==="serverAuth")return null;var g=a;return g}return n}/**
 * @license
 * Copyright 2019 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */function W(){var t=De(L);t.INTERNAL=z(z({},t.INTERNAL),{createFirebaseNamespace:W,extendNamespace:e,createSubscribe:oe,ErrorFactory:T,deepExtend:C});function e(r){C(t,r)}return t}var M=W();/**
 * @license
 * Copyright 2019 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var ze=function(){function t(e){this.container=e}return t.prototype.getPlatformInfoString=function(){var e=this.container.getProviders();return e.map(function(r){if(Te(r)){var n=r.getImmediate();return n.library+"/"+n.version}else return null}).filter(function(r){return r}).join(" ")},t}();function Te(t){var e=t.getComponent();return(e==null?void 0:e.type)==="VERSION"}/**
 * @license
 * Copyright 2019 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */function je(t,e){t.INTERNAL.registerComponent(new j("platform-logger",function(r){return new ze(r)},"PRIVATE")),t.registerVersion(V,be,e),t.registerVersion("fire-js","")}/**
 * @license
 * Copyright 2017 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */if(ee()&&self.firebase!==void 0){A.warn(`
    Warning: Firebase is already defined in the global scope. Please make sure
    Firebase library is only loaded once.
  `);var B=self.firebase.SDK_VERSION;B&&B.indexOf("LITE")>=0&&A.warn(`
    Warning: You are trying to load Firebase while using Firebase Performance standalone script.
    You should load Firebase Performance with this instance of Firebase to avoid loading duplicate code.
    `)}var He=M.initializeApp;M.initializeApp=function(){for(var t=[],e=0;e<arguments.length;e++)t[e]=arguments[e];return Q()&&A.warn(`
      Warning: This is a browser-targeted Firebase bundle but it appears it is being
      run in a Node environment.  If running in a Node environment, make sure you
      are using the bundle specified by the "main" field in package.json.
      
      If you are using Webpack, you can specify "main" as the first item in
      "resolve.mainFields":
      https://webpack.js.org/configuration/resolve/#resolvemainfields
      
      If using Rollup, use the @rollup/plugin-node-resolve plugin and specify "main"
      as the first item in "mainFields", e.g. ['main', 'module'].
      https://github.com/rollup/@rollup/plugin-node-resolve
      `),He.apply(void 0,t)};var Me=M;je(Me);export{j as C,re as F,ve as L,Be as a,Ue as b,Ve as c,We as d,ke as e,Me as f,F as g,Ge as h,$e as i,u as j};
//# sourceMappingURL=index.esm-BVwnWB-V.js.map
