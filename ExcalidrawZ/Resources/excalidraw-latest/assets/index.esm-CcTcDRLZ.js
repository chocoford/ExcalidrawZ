import{F as Ne,h as E,C as De,f as be}from"./index.esm-BnJJ2GwU.js";import{_ as He,d as I,a as ze,e as q,f as fe}from"./index-4m_yizBt.js";/**
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
 */var ye="firebasestorage.googleapis.com",Re="storageBucket",Xe=2*60*1e3,Ge=10*60*1e3,p=function(t){He(e,t);function e(r,n){var a=t.call(this,ee(r),"Firebase Storage: "+n+" ("+ee(r)+")")||this;return a.customData={serverResponse:null},Object.setPrototypeOf(a,e.prototype),a}return e.prototype._codeEquals=function(r){return ee(r)===this.code},Object.defineProperty(e.prototype,"message",{get:function(){return this.customData.serverResponse?this.message+`
`+this.customData.serverResponse:this.message},enumerable:!1,configurable:!0}),Object.defineProperty(e.prototype,"serverResponse",{get:function(){return this.customData.serverResponse},set:function(r){this.customData.serverResponse=r},enumerable:!1,configurable:!0}),e}(Ne);function ee(t){return"storage/"+t}function oe(){var t="An unknown error occurred, please check the error payload for server response.";return new p("unknown",t)}function $e(t){return new p("object-not-found","Object '"+t+"' does not exist.")}function We(t){return new p("quota-exceeded","Quota for bucket '"+t+"' exceeded, please view quota on https://firebase.google.com/pricing/.")}function Ke(){var t="User is not authenticated, please authenticate using Firebase Authentication and try again.";return new p("unauthenticated",t)}function Ye(t){return new p("unauthorized","User does not have permission to access '"+t+"'.")}function Ze(){return new p("retry-limit-exceeded","Max retry time for operation exceeded, please try again.")}function we(){return new p("canceled","User canceled the upload/download.")}function Je(t){return new p("invalid-url","Invalid URL '"+t+"'.")}function Qe(t){return new p("invalid-default-bucket","Invalid default bucket '"+t+"'.")}function Ve(){return new p("no-default-bucket","No default bucket found. Did you set the '"+Re+"' property when initializing the app?")}function ke(){return new p("cannot-slice-blob","Cannot slice blob for upload. Please retry the upload.")}function et(){return new p("server-file-wrong-size","Server recorded incorrect upload file size, please retry the upload.")}function tt(){return new p("no-download-url","The given file does not have any download URLs.")}function C(t){return new p("invalid-argument",t)}function Te(){return new p("app-deleted","The Firebase app was deleted.")}function Se(t){return new p("invalid-root-operation","The operation '"+t+"' cannot be performed on a root reference, create a non-root reference using child, such as .child('file.png').")}function M(t,e){return new p("invalid-format","String does not match format '"+t+"': "+e)}function H(t){throw new p("internal-error","Internal error: "+t)}/**
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
 */var w={RAW:"raw",BASE64:"base64",BASE64URL:"base64url",DATA_URL:"data_url"},te=function(){function t(e,r){this.data=e,this.contentType=r||null}return t}();function Pe(t,e){switch(t){case w.RAW:return new te(Ue(e));case w.BASE64:case w.BASE64URL:return new te(xe(t,e));case w.DATA_URL:return new te(nt(e),at(e))}throw oe()}function Ue(t){for(var e=[],r=0;r<t.length;r++){var n=t.charCodeAt(r);if(n<=127)e.push(n);else if(n<=2047)e.push(192|n>>6,128|n&63);else if((n&64512)===55296){var a=r<t.length-1&&(t.charCodeAt(r+1)&64512)===56320;if(!a)e.push(239,191,189);else{var o=n,i=t.charCodeAt(++r);n=65536|(o&1023)<<10|i&1023,e.push(240|n>>18,128|n>>12&63,128|n>>6&63,128|n&63)}}else(n&64512)===56320?e.push(239,191,189):e.push(224|n>>12,128|n>>6&63,128|n&63)}return new Uint8Array(e)}function rt(t){var e;try{e=decodeURIComponent(t)}catch{throw M(w.DATA_URL,"Malformed data URL.")}return Ue(e)}function xe(t,e){switch(t){case w.BASE64:{var r=e.indexOf("-")!==-1,n=e.indexOf("_")!==-1;if(r||n){var a=r?"-":"_";throw M(t,"Invalid character '"+a+"' found: is it base64url encoded?")}break}case w.BASE64URL:{var o=e.indexOf("+")!==-1,i=e.indexOf("/")!==-1;if(o||i){var a=o?"+":"/";throw M(t,"Invalid character '"+a+"' found: is it base64 encoded?")}e=e.replace(/-/g,"+").replace(/_/g,"/");break}}var u;try{u=atob(e)}catch{throw M(t,"Invalid character found")}for(var s=new Uint8Array(u.length),l=0;l<u.length;l++)s[l]=u.charCodeAt(l);return s}var Ee=function(){function t(e){this.base64=!1,this.contentType=null;var r=e.match(/^data:([^,]+)?,/);if(r===null)throw M(w.DATA_URL,"Must be formatted 'data:[<mediatype>][;base64],<data>");var n=r[1]||null;n!=null&&(this.base64=ot(n,";base64"),this.contentType=this.base64?n.substring(0,n.length-7):n),this.rest=e.substring(e.indexOf(",")+1)}return t}();function nt(t){var e=new Ee(t);return e.base64?xe(w.BASE64,e.rest):rt(e.rest)}function at(t){var e=new Ee(t);return e.contentType}function ot(t,e){var r=t.length>=e.length;return r?t.substring(t.length-e.length)===e:!1}/**
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
 */var it={STATE_CHANGED:"state_changed"},g={RUNNING:"running",PAUSED:"paused",SUCCESS:"success",CANCELED:"canceled",ERROR:"error"};function re(t){switch(t){case"running":case"pausing":case"canceling":return g.RUNNING;case"paused":return g.PAUSED;case"success":return g.SUCCESS;case"canceled":return g.CANCELED;case"error":return g.ERROR;default:return g.ERROR}}/**
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
 */var A;(function(t){t[t.NO_ERROR=0]="NO_ERROR",t[t.NETWORK_ERROR=1]="NETWORK_ERROR",t[t.ABORT=2]="ABORT"})(A||(A={}));/**
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
 */var st=function(){function t(){var e=this;this.sent_=!1,this.xhr_=new XMLHttpRequest,this.errorCode_=A.NO_ERROR,this.sendPromise_=new Promise(function(r){e.xhr_.addEventListener("abort",function(){e.errorCode_=A.ABORT,r(e)}),e.xhr_.addEventListener("error",function(){e.errorCode_=A.NETWORK_ERROR,r(e)}),e.xhr_.addEventListener("load",function(){r(e)})})}return t.prototype.send=function(e,r,n,a){if(this.sent_)throw H("cannot .send() more than once");if(this.sent_=!0,this.xhr_.open(r,e,!0),a!==void 0)for(var o in a)a.hasOwnProperty(o)&&this.xhr_.setRequestHeader(o,a[o].toString());return n!==void 0?this.xhr_.send(n):this.xhr_.send(),this.sendPromise_},t.prototype.getErrorCode=function(){if(!this.sent_)throw H("cannot .getErrorCode() before sending");return this.errorCode_},t.prototype.getStatus=function(){if(!this.sent_)throw H("cannot .getStatus() before sending");try{return this.xhr_.status}catch{return-1}},t.prototype.getResponseText=function(){if(!this.sent_)throw H("cannot .getResponseText() before sending");return this.xhr_.responseText},t.prototype.abort=function(){this.xhr_.abort()},t.prototype.getResponseHeader=function(e){return this.xhr_.getResponseHeader(e)},t.prototype.addUploadProgressListener=function(e){this.xhr_.upload!=null&&this.xhr_.upload.addEventListener("progress",e)},t.prototype.removeUploadProgressListener=function(e){this.xhr_.upload!=null&&this.xhr_.upload.removeEventListener("progress",e)},t}();/**
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
 */var ut=function(){function t(){}return t.prototype.createXhrIo=function(){return new st},t}();/**
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
 */var k=function(){function t(e,r){this.bucket=e,this.path_=r}return Object.defineProperty(t.prototype,"path",{get:function(){return this.path_},enumerable:!1,configurable:!0}),Object.defineProperty(t.prototype,"isRoot",{get:function(){return this.path.length===0},enumerable:!1,configurable:!0}),t.prototype.fullServerUrl=function(){var e=encodeURIComponent;return"/b/"+e(this.bucket)+"/o/"+e(this.path)},t.prototype.bucketOnlyServerUrl=function(){var e=encodeURIComponent;return"/b/"+e(this.bucket)+"/o"},t.makeFromBucketSpec=function(e){var r;try{r=t.makeFromUrl(e)}catch{return new t(e,"")}if(r.path==="")return r;throw Qe(e)},t.makeFromUrl=function(e){var r=null,n="([A-Za-z0-9.\\-_]+)";function a(P){P.path.charAt(P.path.length-1)==="/"&&(P.path_=P.path_.slice(0,-1))}var o="(/(.*))?$",i=new RegExp("^gs://"+n+o,"i"),u={bucket:1,path:3};function s(P){P.path_=decodeURIComponent(P.path)}for(var l="v[A-Za-z0-9_]+",c=ye.replace(/[.]/g,"\\."),h="(/([^?#]*).*)?$",d=new RegExp("^https?://"+c+"/"+l+"/b/"+n+"/o"+h,"i"),m={bucket:1,path:3},f="(?:storage.googleapis.com|storage.cloud.google.com)",_="([^?#]*)",b=new RegExp("^https?://"+f+"/"+n+"/"+_,"i"),x={bucket:1,path:2},y=[{regex:i,indices:u,postModify:a},{regex:d,indices:m,postModify:s},{regex:b,indices:x,postModify:s}],R=0;R<y.length;R++){var T=y[R],L=T.regex.exec(e);if(L){var D=L[T.indices.bucket],F=L[T.indices.path];F||(F=""),r=new t(D,F),T.postModify(r);break}}if(r==null)throw Je(e);return r},t}(),lt=function(){function t(e){this.promise_=Promise.reject(e)}return t.prototype.getPromise=function(){return this.promise_},t.prototype.cancel=function(e){},t}();/**
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
 */function ct(t,e,r){var n=1,a=null,o=!1,i=0;function u(){return i===2}var s=!1;function l(){for(var f=[],_=0;_<arguments.length;_++)f[_]=arguments[_];s||(s=!0,e.apply(null,f))}function c(f){a=setTimeout(function(){a=null,t(h,u())},f)}function h(f){for(var _=[],b=1;b<arguments.length;b++)_[b-1]=arguments[b];if(!s){if(f){l.call.apply(l,fe([null,f],_));return}var x=u()||o;if(x){l.call.apply(l,fe([null,f],_));return}n<64&&(n*=2);var y;i===1?(i=2,y=0):y=(n+Math.random())*1e3,c(y)}}var d=!1;function m(f){d||(d=!0,!s&&(a!==null?(f||(i=2),clearTimeout(a),c(0)):f||(i=1)))}return c(0),setTimeout(function(){o=!0,m(!0)},r),m}function ft(t){t(!1)}/**
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
 */function ht(t){return t!==void 0}function dt(t){return typeof t=="function"}function pt(t){return typeof t=="object"&&!Array.isArray(t)}function W(t){return typeof t=="string"||t instanceof String}function he(t){return ie()&&t instanceof Blob}function ie(){return typeof Blob<"u"}function ne(t,e,r,n){if(n<e)throw C("Invalid value for '"+t+"'. Expected "+e+" or greater.");if(n>r)throw C("Invalid value for '"+t+"'. Expected "+r+" or less.")}/**
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
 */function O(t){return"https://"+ye+"/v0"+t}function Oe(t){var e=encodeURIComponent,r="?";for(var n in t)if(t.hasOwnProperty(n)){var a=e(n)+"="+e(t[n]);r=r+a+"&"}return r=r.slice(0,-1),r}/**
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
 */var _t=function(){function t(e,r,n,a,o,i,u,s,l,c,h){var d=this;this.pendingXhr_=null,this.backoffId_=null,this.canceled_=!1,this.appDelete_=!1,this.url_=e,this.method_=r,this.headers_=n,this.body_=a,this.successCodes_=o.slice(),this.additionalRetryCodes_=i.slice(),this.callback_=u,this.errorCallback_=s,this.progressCallback_=c,this.timeout_=l,this.pool_=h,this.promise_=new Promise(function(m,f){d.resolve_=m,d.reject_=f,d.start_()})}return t.prototype.start_=function(){var e=this;function r(a,o){if(o){a(!1,new z(!1,null,!0));return}var i=e.pool_.createXhrIo();e.pendingXhr_=i;function u(s){var l=s.loaded,c=s.lengthComputable?s.total:-1;e.progressCallback_!==null&&e.progressCallback_(l,c)}e.progressCallback_!==null&&i.addUploadProgressListener(u),i.send(e.url_,e.method_,e.body_,e.headers_).then(function(s){e.progressCallback_!==null&&s.removeUploadProgressListener(u),e.pendingXhr_=null,s=s;var l=s.getErrorCode()===A.NO_ERROR,c=s.getStatus();if(!l||e.isRetryStatusCode_(c)){var h=s.getErrorCode()===A.ABORT;a(!1,new z(!1,null,h));return}var d=e.successCodes_.indexOf(c)!==-1;a(!0,new z(d,s))})}function n(a,o){var i=e.resolve_,u=e.reject_,s=o.xhr;if(o.wasSuccessCode)try{var l=e.callback_(s,s.getResponseText());ht(l)?i(l):i()}catch(h){u(h)}else if(s!==null){var c=oe();c.serverResponse=s.getResponseText(),e.errorCallback_?u(e.errorCallback_(s,c)):u(c)}else if(o.canceled){var c=e.appDelete_?Te():we();u(c)}else{var c=Ze();u(c)}}this.canceled_?n(!1,new z(!1,null,!0)):this.backoffId_=ct(r,n,this.timeout_)},t.prototype.getPromise=function(){return this.promise_},t.prototype.cancel=function(e){this.canceled_=!0,this.appDelete_=e||!1,this.backoffId_!==null&&ft(this.backoffId_),this.pendingXhr_!==null&&this.pendingXhr_.abort()},t.prototype.isRetryStatusCode_=function(e){var r=e>=500&&e<600,n=[408,429],a=n.indexOf(e)!==-1,o=this.additionalRetryCodes_.indexOf(e)!==-1;return r||a||o},t}(),z=function(){function t(e,r,n){this.wasSuccessCode=e,this.xhr=r,this.canceled=!!n}return t}();function vt(t,e){e!==null&&e.length>0&&(t.Authorization="Firebase "+e)}function gt(t,e){t["X-Firebase-Storage-Version"]="webjs/"+(e??"AppManager")}function mt(t,e){e&&(t["X-Firebase-GMPID"]=e)}function bt(t,e,r,n,a){var o=Oe(t.urlParams),i=t.url+o,u=Object.assign({},t.headers);return mt(u,e),vt(u,r),gt(u,a),new _t(i,t.method,u,t.body,t.successCodes,t.additionalRetryCodes,t.handler,t.errorHandler,t.timeout,t.progressCallback,n)}/**
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
 */function yt(){return typeof BlobBuilder<"u"?BlobBuilder:typeof WebKitBlobBuilder<"u"?WebKitBlobBuilder:void 0}function Rt(){for(var t=[],e=0;e<arguments.length;e++)t[e]=arguments[e];var r=yt();if(r!==void 0){for(var n=new r,a=0;a<t.length;a++)n.append(t[a]);return n.getBlob()}else{if(ie())return new Blob(t);throw new p("unsupported-environment","This browser doesn't seem to support creating Blobs")}}function wt(t,e,r){return t.webkitSlice?t.webkitSlice(e,r):t.mozSlice?t.mozSlice(e,r):t.slice?t.slice(e,r):null}/**
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
 */var se=function(){function t(e,r){var n=0,a="";he(e)?(this.data_=e,n=e.size,a=e.type):e instanceof ArrayBuffer?(r?this.data_=new Uint8Array(e):(this.data_=new Uint8Array(e.byteLength),this.data_.set(new Uint8Array(e))),n=this.data_.length):e instanceof Uint8Array&&(r?this.data_=e:(this.data_=new Uint8Array(e.length),this.data_.set(e)),n=e.length),this.size_=n,this.type_=a}return t.prototype.size=function(){return this.size_},t.prototype.type=function(){return this.type_},t.prototype.slice=function(e,r){if(he(this.data_)){var n=this.data_,a=wt(n,e,r);return a===null?null:new t(a)}else{var o=new Uint8Array(this.data_.buffer,e,r-e);return new t(o,!0)}},t.getBlob=function(){for(var e=[],r=0;r<arguments.length;r++)e[r]=arguments[r];if(ie()){var n=e.map(function(s){return s instanceof t?s.data_:s});return new t(Rt.apply(null,n))}else{var a=e.map(function(s){return W(s)?Pe(w.RAW,s).data:s.data_}),o=0;a.forEach(function(s){o+=s.byteLength});var i=new Uint8Array(o),u=0;return a.forEach(function(s){for(var l=0;l<s.length;l++)i[u++]=s[l]}),new t(i,!0)}},t.prototype.uploadData=function(){return this.data_},t}();/**
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
 */function ue(t){var e;try{e=JSON.parse(t)}catch{return null}return pt(e)?e:null}/**
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
 */function kt(t){if(t.length===0)return null;var e=t.lastIndexOf("/");if(e===-1)return"";var r=t.slice(0,e);return r}function Tt(t,e){var r=e.split("/").filter(function(n){return n.length>0}).join("/");return t.length===0?r:t+"/"+r}function Ce(t){var e=t.lastIndexOf("/",t.length-2);return e===-1?t:t.slice(e+1)}/**
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
 */function St(t,e){return e}var v=function(){function t(e,r,n,a){this.server=e,this.local=r||e,this.writable=!!n,this.xform=a||St}return t}(),X=null;function Pt(t){return!W(t)||t.length<2?t:Ce(t)}function K(){if(X)return X;var t=[];t.push(new v("bucket")),t.push(new v("generation")),t.push(new v("metageneration")),t.push(new v("name","fullPath",!0));function e(o,i){return Pt(i)}var r=new v("name");r.xform=e,t.push(r);function n(o,i){return i!==void 0?Number(i):i}var a=new v("size");return a.xform=n,t.push(a),t.push(new v("timeCreated")),t.push(new v("updated")),t.push(new v("md5Hash",null,!0)),t.push(new v("cacheControl",null,!0)),t.push(new v("contentDisposition",null,!0)),t.push(new v("contentEncoding",null,!0)),t.push(new v("contentLanguage",null,!0)),t.push(new v("contentType",null,!0)),t.push(new v("metadata","customMetadata",!0)),X=t,X}function Ut(t,e){function r(){var n=t.bucket,a=t.fullPath,o=new k(n,a);return e._makeStorageReference(o)}Object.defineProperty(t,"ref",{get:r})}function xt(t,e,r){var n={};n.type="file";for(var a=r.length,o=0;o<a;o++){var i=r[o];n[i.local]=i.xform(n,e[i.server])}return Ut(n,t),n}function Ae(t,e,r){var n=ue(e);if(n===null)return null;var a=n;return xt(t,a,r)}function Et(t,e){var r=ue(e);if(r===null||!W(r.downloadTokens))return null;var n=r.downloadTokens;if(n.length===0)return null;var a=encodeURIComponent,o=n.split(","),i=o.map(function(u){var s=t.bucket,l=t.fullPath,c="/b/"+a(s)+"/o/"+a(l),h=O(c),d=Oe({alt:"media",token:u});return h+d});return i[0]}function le(t,e){for(var r={},n=e.length,a=0;a<n;a++){var o=e[a];o.writable&&(r[o.server]=t[o.local])}return JSON.stringify(r)}/**
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
 */var de="prefixes",pe="items";function Ot(t,e,r){var n={prefixes:[],items:[],nextPageToken:r.nextPageToken};if(r[de])for(var a=0,o=r[de];a<o.length;a++){var i=o[a],u=i.replace(/\/$/,""),s=t._makeStorageReference(new k(e,u));n.prefixes.push(s)}if(r[pe])for(var l=0,c=r[pe];l<c.length;l++){var h=c[l],s=t._makeStorageReference(new k(e,h.name));n.items.push(s)}return n}function Ct(t,e,r){var n=ue(r);if(n===null)return null;var a=n;return Ot(t,e,a)}var U=function(){function t(e,r,n,a){this.url=e,this.method=r,this.handler=n,this.timeout=a,this.urlParams={},this.headers={},this.body=null,this.errorHandler=null,this.progressCallback=null,this.successCodes=[200],this.additionalRetryCodes=[]}return t}();/**
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
 */function S(t){if(!t)throw oe()}function Y(t,e){function r(n,a){var o=Ae(t,a,e);return S(o!==null),o}return r}function At(t,e){function r(n,a){var o=Ct(t,e,a);return S(o!==null),o}return r}function It(t,e){function r(n,a){var o=Ae(t,a,e);return S(o!==null),Et(o,a)}return r}function j(t){function e(r,n){var a;return r.getStatus()===401?a=Ke():r.getStatus()===402?a=We(t.bucket):r.getStatus()===403?a=Ye(t.path):a=n,a.serverResponse=n.serverResponse,a}return e}function Z(t){var e=j(t);function r(n,a){var o=e(n,a);return n.getStatus()===404&&(o=$e(t.path)),o.serverResponse=a.serverResponse,o}return r}function Ie(t,e,r){var n=e.fullServerUrl(),a=O(n),o="GET",i=t.maxOperationRetryTime,u=new U(a,o,Y(t,r),i);return u.errorHandler=Z(e),u}function qt(t,e,r,n,a){var o={};e.isRoot?o.prefix="":o.prefix=e.path+"/",r.length>0&&(o.delimiter=r),n&&(o.pageToken=n),a&&(o.maxResults=a);var i=e.bucketOnlyServerUrl(),u=O(i),s="GET",l=t.maxOperationRetryTime,c=new U(u,s,At(t,e.bucket),l);return c.urlParams=o,c.errorHandler=j(e),c}function Bt(t,e,r){var n=e.fullServerUrl(),a=O(n),o="GET",i=t.maxOperationRetryTime,u=new U(a,o,It(t,r),i);return u.errorHandler=Z(e),u}function jt(t,e,r,n){var a=e.fullServerUrl(),o=O(a),i="PATCH",u=le(r,n),s={"Content-Type":"application/json; charset=utf-8"},l=t.maxOperationRetryTime,c=new U(o,i,Y(t,n),l);return c.headers=s,c.body=u,c.errorHandler=Z(e),c}function Lt(t,e){var r=e.fullServerUrl(),n=O(r),a="DELETE",o=t.maxOperationRetryTime;function i(s,l){}var u=new U(n,a,i,o);return u.successCodes=[200,204],u.errorHandler=Z(e),u}function Ft(t,e){return t&&t.contentType||e&&e.type()||"application/octet-stream"}function qe(t,e,r){var n=Object.assign({},r);return n.fullPath=t.path,n.size=e.size(),n.contentType||(n.contentType=Ft(null,e)),n}function Mt(t,e,r,n,a){var o=e.bucketOnlyServerUrl(),i={"X-Goog-Upload-Protocol":"multipart"};function u(){for(var R="",T=0;T<2;T++)R=R+Math.random().toString().slice(2);return R}var s=u();i["Content-Type"]="multipart/related; boundary="+s;var l=qe(e,n,a),c=le(l,r),h="--"+s+`\r
Content-Type: application/json; charset=utf-8\r
\r
`+c+`\r
--`+s+`\r
Content-Type: `+l.contentType+`\r
\r
`,d=`\r
--`+s+"--",m=se.getBlob(h,n,d);if(m===null)throw ke();var f={name:l.fullPath},_=O(o),b="POST",x=t.maxUploadRetryTime,y=new U(_,b,Y(t,r),x);return y.urlParams=f,y.headers=i,y.body=m.uploadData(),y.errorHandler=j(e),y}var $=function(){function t(e,r,n,a){this.current=e,this.total=r,this.finalized=!!n,this.metadata=a||null}return t}();function ce(t,e){var r=null;try{r=t.getResponseHeader("X-Goog-Upload-Status")}catch{S(!1)}var n=e||["active"];return S(!!r&&n.indexOf(r)!==-1),r}function Nt(t,e,r,n,a){var o=e.bucketOnlyServerUrl(),i=qe(e,n,a),u={name:i.fullPath},s=O(o),l="POST",c={"X-Goog-Upload-Protocol":"resumable","X-Goog-Upload-Command":"start","X-Goog-Upload-Header-Content-Length":n.size(),"X-Goog-Upload-Header-Content-Type":i.contentType,"Content-Type":"application/json; charset=utf-8"},h=le(i,r),d=t.maxUploadRetryTime;function m(_){ce(_);var b;try{b=_.getResponseHeader("X-Goog-Upload-URL")}catch{S(!1)}return S(W(b)),b}var f=new U(s,l,m,d);return f.urlParams=u,f.headers=c,f.body=h,f.errorHandler=j(e),f}function Dt(t,e,r,n){var a={"X-Goog-Upload-Command":"query"};function o(l){var c=ce(l,["active","final"]),h=null;try{h=l.getResponseHeader("X-Goog-Upload-Size-Received")}catch{S(!1)}h||S(!1);var d=Number(h);return S(!isNaN(d)),new $(d,n.size(),c==="final")}var i="POST",u=t.maxUploadRetryTime,s=new U(r,i,o,u);return s.headers=a,s.errorHandler=j(e),s}var _e=256*1024;function Ht(t,e,r,n,a,o,i,u){var s=new $(0,0);if(i?(s.current=i.current,s.total=i.total):(s.current=0,s.total=n.size()),n.size()!==s.total)throw et();var l=s.total-s.current,c=l;a>0&&(c=Math.min(c,a));var h=s.current,d=h+c,m=c===l?"upload, finalize":"upload",f={"X-Goog-Upload-Command":m,"X-Goog-Upload-Offset":s.current},_=n.slice(h,d);if(_===null)throw ke();function b(T,L){var D=ce(T,["active","final"]),F=s.current+c,P=n.size(),V;return D==="final"?V=Y(e,o)(T,L):V=null,new $(F,P,D==="final",V)}var x="POST",y=e.maxUploadRetryTime,R=new U(r,x,b,y);return R.headers=f,R.body=_.uploadData(),R.progressCallback=u||null,R.errorHandler=j(t),R}/**
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
 */var zt=function(){function t(e,r,n){var a=dt(e)||r!=null||n!=null;if(a)this.next=e,this.error=r,this.complete=n;else{var o=e;this.next=o.next,this.error=o.error,this.complete=o.complete}}return t}();/**
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
 */function B(t){return function(){for(var e=[],r=0;r<arguments.length;r++)e[r]=arguments[r];Promise.resolve().then(function(){return t.apply(void 0,e)})}}/**
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
 */var Be=function(){function t(e,r,n){var a=this;n===void 0&&(n=null),this._transferred=0,this._needToFetchStatus=!1,this._needToFetchMetadata=!1,this._observers=[],this._error=void 0,this._uploadUrl=void 0,this._request=void 0,this._chunkMultiplier=1,this._resolve=void 0,this._reject=void 0,this._ref=e,this._blob=r,this._metadata=n,this._mappings=K(),this._resumable=this._shouldDoResumable(this._blob),this._state="running",this._errorHandler=function(o){a._request=void 0,a._chunkMultiplier=1,o._codeEquals("canceled")?(a._needToFetchStatus=!0,a.completeTransitions_()):(a._error=o,a._transition("error"))},this._metadataErrorHandler=function(o){a._request=void 0,o._codeEquals("canceled")?a.completeTransitions_():(a._error=o,a._transition("error"))},this._promise=new Promise(function(o,i){a._resolve=o,a._reject=i,a._start()}),this._promise.then(null,function(){})}return t.prototype._makeProgressCallback=function(){var e=this,r=this._transferred;return function(n){return e._updateProgress(r+n)}},t.prototype._shouldDoResumable=function(e){return e.size()>256*1024},t.prototype._start=function(){this._state==="running"&&this._request===void 0&&(this._resumable?this._uploadUrl===void 0?this._createResumable():this._needToFetchStatus?this._fetchStatus():this._needToFetchMetadata?this._fetchMetadata():this._continueUpload():this._oneShotUpload())},t.prototype._resolveToken=function(e){var r=this;this._ref.storage._getAuthToken().then(function(n){switch(r._state){case"running":e(n);break;case"canceling":r._transition("canceled");break;case"pausing":r._transition("paused");break}})},t.prototype._createResumable=function(){var e=this;this._resolveToken(function(r){var n=Nt(e._ref.storage,e._ref._location,e._mappings,e._blob,e._metadata),a=e._ref.storage._makeRequest(n,r);e._request=a,a.getPromise().then(function(o){e._request=void 0,e._uploadUrl=o,e._needToFetchStatus=!1,e.completeTransitions_()},e._errorHandler)})},t.prototype._fetchStatus=function(){var e=this,r=this._uploadUrl;this._resolveToken(function(n){var a=Dt(e._ref.storage,e._ref._location,r,e._blob),o=e._ref.storage._makeRequest(a,n);e._request=o,o.getPromise().then(function(i){i=i,e._request=void 0,e._updateProgress(i.current),e._needToFetchStatus=!1,i.finalized&&(e._needToFetchMetadata=!0),e.completeTransitions_()},e._errorHandler)})},t.prototype._continueUpload=function(){var e=this,r=_e*this._chunkMultiplier,n=new $(this._transferred,this._blob.size()),a=this._uploadUrl;this._resolveToken(function(o){var i;try{i=Ht(e._ref._location,e._ref.storage,a,e._blob,r,e._mappings,n,e._makeProgressCallback())}catch(s){e._error=s,e._transition("error");return}var u=e._ref.storage._makeRequest(i,o);e._request=u,u.getPromise().then(function(s){e._increaseMultiplier(),e._request=void 0,e._updateProgress(s.current),s.finalized?(e._metadata=s.metadata,e._transition("success")):e.completeTransitions_()},e._errorHandler)})},t.prototype._increaseMultiplier=function(){var e=_e*this._chunkMultiplier;e<32*1024*1024&&(this._chunkMultiplier*=2)},t.prototype._fetchMetadata=function(){var e=this;this._resolveToken(function(r){var n=Ie(e._ref.storage,e._ref._location,e._mappings),a=e._ref.storage._makeRequest(n,r);e._request=a,a.getPromise().then(function(o){e._request=void 0,e._metadata=o,e._transition("success")},e._metadataErrorHandler)})},t.prototype._oneShotUpload=function(){var e=this;this._resolveToken(function(r){var n=Mt(e._ref.storage,e._ref._location,e._mappings,e._blob,e._metadata),a=e._ref.storage._makeRequest(n,r);e._request=a,a.getPromise().then(function(o){e._request=void 0,e._metadata=o,e._updateProgress(e._blob.size()),e._transition("success")},e._errorHandler)})},t.prototype._updateProgress=function(e){var r=this._transferred;this._transferred=e,this._transferred!==r&&this._notifyObservers()},t.prototype._transition=function(e){if(this._state!==e)switch(e){case"canceling":this._state=e,this._request!==void 0&&this._request.cancel();break;case"pausing":this._state=e,this._request!==void 0&&this._request.cancel();break;case"running":var r=this._state==="paused";this._state=e,r&&(this._notifyObservers(),this._start());break;case"paused":this._state=e,this._notifyObservers();break;case"canceled":this._error=we(),this._state=e,this._notifyObservers();break;case"error":this._state=e,this._notifyObservers();break;case"success":this._state=e,this._notifyObservers();break}},t.prototype.completeTransitions_=function(){switch(this._state){case"pausing":this._transition("paused");break;case"canceling":this._transition("canceled");break;case"running":this._start();break}},Object.defineProperty(t.prototype,"snapshot",{get:function(){var e=re(this._state);return{bytesTransferred:this._transferred,totalBytes:this._blob.size(),state:e,metadata:this._metadata,task:this,ref:this._ref}},enumerable:!1,configurable:!0}),t.prototype.on=function(e,r,n,a){var o=this,i=new zt(r,n,a);return this._addObserver(i),function(){o._removeObserver(i)}},t.prototype.then=function(e,r){return this._promise.then(e,r)},t.prototype.catch=function(e){return this.then(null,e)},t.prototype._addObserver=function(e){this._observers.push(e),this._notifyObserver(e)},t.prototype._removeObserver=function(e){var r=this._observers.indexOf(e);r!==-1&&this._observers.splice(r,1)},t.prototype._notifyObservers=function(){var e=this;this._finishPromise();var r=this._observers.slice();r.forEach(function(n){e._notifyObserver(n)})},t.prototype._finishPromise=function(){if(this._resolve!==void 0){var e=!0;switch(re(this._state)){case g.SUCCESS:B(this._resolve.bind(null,this.snapshot))();break;case g.CANCELED:case g.ERROR:var r=this._reject;B(r.bind(null,this._error))();break;default:e=!1;break}e&&(this._resolve=void 0,this._reject=void 0)}},t.prototype._notifyObserver=function(e){var r=re(this._state);switch(r){case g.RUNNING:case g.PAUSED:e.next&&B(e.next.bind(e,this.snapshot))();break;case g.SUCCESS:e.complete&&B(e.complete.bind(e))();break;case g.CANCELED:case g.ERROR:e.error&&B(e.error.bind(e,this._error))();break;default:e.error&&B(e.error.bind(e,this._error))()}},t.prototype.resume=function(){var e=this._state==="paused"||this._state==="pausing";return e&&this._transition("running"),e},t.prototype.pause=function(){var e=this._state==="running";return e&&this._transition("pausing"),e},t.prototype.cancel=function(){var e=this._state==="running"||this._state==="pausing";return e&&this._transition("canceling"),e},t}();/**
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
 */var J=function(){function t(e,r){this._service=e,r instanceof k?this._location=r:this._location=k.makeFromUrl(r)}return t.prototype.toString=function(){return"gs://"+this._location.bucket+"/"+this._location.path},t.prototype._newRef=function(e,r){return new t(e,r)},Object.defineProperty(t.prototype,"root",{get:function(){var e=new k(this._location.bucket,"");return this._newRef(this._service,e)},enumerable:!1,configurable:!0}),Object.defineProperty(t.prototype,"bucket",{get:function(){return this._location.bucket},enumerable:!1,configurable:!0}),Object.defineProperty(t.prototype,"fullPath",{get:function(){return this._location.path},enumerable:!1,configurable:!0}),Object.defineProperty(t.prototype,"name",{get:function(){return Ce(this._location.path)},enumerable:!1,configurable:!0}),Object.defineProperty(t.prototype,"storage",{get:function(){return this._service},enumerable:!1,configurable:!0}),Object.defineProperty(t.prototype,"parent",{get:function(){var e=kt(this._location.path);if(e===null)return null;var r=new k(this._location.bucket,e);return new t(this._service,r)},enumerable:!1,configurable:!0}),t.prototype._throwIfRoot=function(e){if(this._location.path==="")throw Se(e)},t}();function Xt(t,e,r){return t._throwIfRoot("uploadBytesResumable"),new Be(t,new se(e),r)}function Gt(t){var e={prefixes:[],items:[]};return je(t,e).then(function(){return e})}function je(t,e,r){return I(this,void 0,void 0,function(){var n,a,o,i;return q(this,function(u){switch(u.label){case 0:return n={pageToken:r},[4,Le(t,n)];case 1:return a=u.sent(),(o=e.prefixes).push.apply(o,a.prefixes),(i=e.items).push.apply(i,a.items),a.nextPageToken==null?[3,3]:[4,je(t,e,a.nextPageToken)];case 2:u.sent(),u.label=3;case 3:return[2]}})})}function Le(t,e){return I(this,void 0,void 0,function(){var r,n,a;return q(this,function(o){switch(o.label){case 0:return e!=null&&typeof e.maxResults=="number"&&ne("options.maxResults",1,1e3,e.maxResults),[4,t.storage._getAuthToken()];case 1:return r=o.sent(),n=e||{},a=qt(t.storage,t._location,"/",n.pageToken,n.maxResults),[2,t.storage._makeRequest(a,r).getPromise()]}})})}function $t(t){return I(this,void 0,void 0,function(){var e,r;return q(this,function(n){switch(n.label){case 0:return t._throwIfRoot("getMetadata"),[4,t.storage._getAuthToken()];case 1:return e=n.sent(),r=Ie(t.storage,t._location,K()),[2,t.storage._makeRequest(r,e).getPromise()]}})})}function Wt(t,e){return I(this,void 0,void 0,function(){var r,n;return q(this,function(a){switch(a.label){case 0:return t._throwIfRoot("updateMetadata"),[4,t.storage._getAuthToken()];case 1:return r=a.sent(),n=jt(t.storage,t._location,e,K()),[2,t.storage._makeRequest(n,r).getPromise()]}})})}function Kt(t){return I(this,void 0,void 0,function(){var e,r;return q(this,function(n){switch(n.label){case 0:return t._throwIfRoot("getDownloadURL"),[4,t.storage._getAuthToken()];case 1:return e=n.sent(),r=Bt(t.storage,t._location,K()),[2,t.storage._makeRequest(r,e).getPromise().then(function(a){if(a===null)throw tt();return a})]}})})}function Yt(t){return I(this,void 0,void 0,function(){var e,r;return q(this,function(n){switch(n.label){case 0:return t._throwIfRoot("deleteObject"),[4,t.storage._getAuthToken()];case 1:return e=n.sent(),r=Lt(t.storage,t._location),[2,t.storage._makeRequest(r,e).getPromise()]}})})}function Fe(t,e){var r=Tt(t._location.path,e),n=new k(t._location.bucket,r);return new J(t.storage,n)}/**
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
 */function ae(t){return/^[A-Za-z]+:\/\//.test(t)}function Zt(t,e){return new J(t,e)}function Me(t,e){if(t instanceof Q){var r=t;if(r._bucket==null)throw Ve();var n=new J(r,r._bucket);return e!=null?Me(n,e):n}else if(e!==void 0){if(e.includes(".."))throw C('`path` param cannot contain ".."');return Fe(t,e)}else return t}function Jt(t,e){if(e&&ae(e)){if(t instanceof Q)return Zt(t,e);throw C("To use ref(service, url), the first argument must be a Storage instance.")}else return Me(t,e)}function Qt(t){var e=t==null?void 0:t[Re];return e==null?null:k.makeFromBucketSpec(e)}var Q=function(){function t(e,r,n,a,o){this.app=e,this._authProvider=r,this._pool=n,this._url=a,this._firebaseVersion=o,this._bucket=null,this._appId=null,this._deleted=!1,this._maxOperationRetryTime=Xe,this._maxUploadRetryTime=Ge,this._requests=new Set,a!=null?this._bucket=k.makeFromBucketSpec(a):this._bucket=Qt(this.app.options)}return Object.defineProperty(t.prototype,"maxUploadRetryTime",{get:function(){return this._maxUploadRetryTime},set:function(e){ne("time",0,Number.POSITIVE_INFINITY,e),this._maxUploadRetryTime=e},enumerable:!1,configurable:!0}),Object.defineProperty(t.prototype,"maxOperationRetryTime",{get:function(){return this._maxOperationRetryTime},set:function(e){ne("time",0,Number.POSITIVE_INFINITY,e),this._maxOperationRetryTime=e},enumerable:!1,configurable:!0}),t.prototype._getAuthToken=function(){return I(this,void 0,void 0,function(){var e,r;return q(this,function(n){switch(n.label){case 0:return e=this._authProvider.getImmediate({optional:!0}),e?[4,e.getToken()]:[3,2];case 1:if(r=n.sent(),r!==null)return[2,r.accessToken];n.label=2;case 2:return[2,null]}})})},t.prototype._delete=function(){return this._deleted=!0,this._requests.forEach(function(e){return e.cancel()}),this._requests.clear(),Promise.resolve()},t.prototype._makeStorageReference=function(e){return new J(this,e)},t.prototype._makeRequest=function(e,r){var n=this;if(this._deleted)return new lt(Te());var a=bt(e,this._appId,r,this._pool,this._firebaseVersion);return this._requests.add(a),a.getPromise().then(function(){return n._requests.delete(a)},function(){return n._requests.delete(a)}),a},t}();/**
 * @license
 * Copyright 2020 Google LLC
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
 */function Vt(t,e,r){return t=E(t),Xt(t,e,r)}function er(t){return t=E(t),$t(t)}function tr(t,e){return t=E(t),Wt(t,e)}function rr(t,e){return t=E(t),Le(t,e)}function nr(t){return t=E(t),Gt(t)}function ar(t){return t=E(t),Kt(t)}function or(t){return t=E(t),Yt(t)}function ve(t,e){return t=E(t),Jt(t,e)}function ir(t,e){return Fe(t,e)}/**
 * @license
 * Copyright 2020 Google LLC
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
 */var G=function(){function t(e,r,n){this._delegate=e,this.task=r,this.ref=n}return Object.defineProperty(t.prototype,"bytesTransferred",{get:function(){return this._delegate.bytesTransferred},enumerable:!1,configurable:!0}),Object.defineProperty(t.prototype,"metadata",{get:function(){return this._delegate.metadata},enumerable:!1,configurable:!0}),Object.defineProperty(t.prototype,"state",{get:function(){return this._delegate.state},enumerable:!1,configurable:!0}),Object.defineProperty(t.prototype,"totalBytes",{get:function(){return this._delegate.totalBytes},enumerable:!1,configurable:!0}),t}();/**
 * @license
 * Copyright 2020 Google LLC
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
 */var ge=function(){function t(e,r){this._delegate=e,this._ref=r,this.cancel=this._delegate.cancel.bind(this._delegate),this.catch=this._delegate.catch.bind(this._delegate),this.pause=this._delegate.pause.bind(this._delegate),this.resume=this._delegate.resume.bind(this._delegate)}return Object.defineProperty(t.prototype,"snapshot",{get:function(){return new G(this._delegate.snapshot,this,this._ref)},enumerable:!1,configurable:!0}),t.prototype.then=function(e,r){var n=this;return this._delegate.then(function(a){if(e)return e(new G(a,n,n._ref))},r)},t.prototype.on=function(e,r,n,a){var o=this,i=void 0;return r&&(typeof r=="function"?i=function(u){return r(new G(u,o,o._ref))}:i={next:r.next?function(u){return r.next(new G(u,o,o._ref))}:void 0,complete:r.complete||void 0,error:r.error||void 0}),this._delegate.on(e,i,n||void 0,a||void 0)},t}(),me=function(){function t(e,r){this._delegate=e,this._service=r}return Object.defineProperty(t.prototype,"prefixes",{get:function(){var e=this;return this._delegate.prefixes.map(function(r){return new N(r,e._service)})},enumerable:!1,configurable:!0}),Object.defineProperty(t.prototype,"items",{get:function(){var e=this;return this._delegate.items.map(function(r){return new N(r,e._service)})},enumerable:!1,configurable:!0}),Object.defineProperty(t.prototype,"nextPageToken",{get:function(){return this._delegate.nextPageToken||null},enumerable:!1,configurable:!0}),t}();/**
 * @license
 * Copyright 2020 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *  http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */var N=function(){function t(e,r){this._delegate=e,this.storage=r}return Object.defineProperty(t.prototype,"name",{get:function(){return this._delegate.name},enumerable:!1,configurable:!0}),Object.defineProperty(t.prototype,"bucket",{get:function(){return this._delegate.bucket},enumerable:!1,configurable:!0}),Object.defineProperty(t.prototype,"fullPath",{get:function(){return this._delegate.fullPath},enumerable:!1,configurable:!0}),t.prototype.toString=function(){return this._delegate.toString()},t.prototype.child=function(e){var r=ir(this._delegate,e);return new t(r,this.storage)},Object.defineProperty(t.prototype,"root",{get:function(){return new t(this._delegate.root,this.storage)},enumerable:!1,configurable:!0}),Object.defineProperty(t.prototype,"parent",{get:function(){var e=this._delegate.parent;return e==null?null:new t(e,this.storage)},enumerable:!1,configurable:!0}),t.prototype.put=function(e,r){return this._throwIfRoot("put"),new ge(Vt(this._delegate,e,r),this)},t.prototype.putString=function(e,r,n){r===void 0&&(r=w.RAW),this._throwIfRoot("putString");var a=Pe(r,e),o=ze({},n);return o.contentType==null&&a.contentType!=null&&(o.contentType=a.contentType),new ge(new Be(this._delegate,new se(a.data,!0),o),this)},t.prototype.listAll=function(){var e=this;return nr(this._delegate).then(function(r){return new me(r,e.storage)})},t.prototype.list=function(e){var r=this;return rr(this._delegate,e||void 0).then(function(n){return new me(n,r.storage)})},t.prototype.getMetadata=function(){return er(this._delegate)},t.prototype.updateMetadata=function(e){return tr(this._delegate,e)},t.prototype.getDownloadURL=function(){return ar(this._delegate)},t.prototype.delete=function(){return this._throwIfRoot("delete"),or(this._delegate)},t.prototype._throwIfRoot=function(e){if(this._delegate._location.path==="")throw Se(e)},t}();/**
 * @license
 * Copyright 2020 Google LLC
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
 */var sr=function(){function t(e,r){var n=this;this.app=e,this._delegate=r,this.INTERNAL={delete:function(){return n._delegate._delete()}}}return Object.defineProperty(t.prototype,"maxOperationRetryTime",{get:function(){return this._delegate.maxOperationRetryTime},enumerable:!1,configurable:!0}),Object.defineProperty(t.prototype,"maxUploadRetryTime",{get:function(){return this._delegate.maxUploadRetryTime},enumerable:!1,configurable:!0}),t.prototype.ref=function(e){if(ae(e))throw C("ref() expected a child path but got a URL, use refFromURL instead.");return new N(ve(this._delegate,e),this)},t.prototype.refFromURL=function(e){if(!ae(e))throw C("refFromURL() expected a full URL but got a child path, use ref() instead.");try{k.makeFromUrl(e)}catch{throw C("refFromUrl() expected a valid full URL but got an invalid one.")}return new N(ve(this._delegate,e),this)},t.prototype.setMaxUploadRetryTime=function(e){this._delegate.maxUploadRetryTime=e},t.prototype.setMaxOperationRetryTime=function(e){this._delegate.maxOperationRetryTime=e},t}(),ur="@firebase/storage",lr="0.4.7";/**
 * @license
 * Copyright 2020 Google LLC
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
 */var cr="storage";function fr(t,e){var r=e.instanceIdentifier,n=t.getProvider("app").getImmediate(),a=t.getProvider("auth-internal"),o=new sr(n,new Q(n,a,new ut,r,be.SDK_VERSION));return o}function hr(t){var e={TaskState:g,TaskEvent:it,StringFormat:w,Storage:Q,Reference:N};t.INTERNAL.registerComponent(new De(cr,fr,"PUBLIC").setServiceProps(e).setMultipleInstances(!0)),t.registerVersion(ur,lr)}hr(be);
//# sourceMappingURL=index.esm-CcTcDRLZ.js.map
