const originalConsole = console;
const methods = ['log', 'debug', 'info', 'warn', 'error'];

methods.forEach(function (method) {
    const originalMethod = console[method];
    console[method] = function (...args) {
        originalMethod.apply(originalConsole, args);
        try {
            window.webkit.messageHandlers.consoleHandler.postMessage({
                event: 'log',
                method: method,
                args: args.map(arg => JSON.stringify(arg))
            });
        } catch (e) {
            console.error('Error posting message...', e);
        }
    };
});


window.onerror = function(message, source, lineno, colno, error) {
   console.error(message, source, lineno, colno, error);
};
