#' @include HandlerStack.R
NULL

#' Generate a New App Object
#' 
#' The Fire generator creates a new 'Fire'-object, which is the the class 
#' containing all app logic. The class is based on the R6 oo-system and is thus
#' reference-based with methods and data attached to each object, in contrast to
#' the more well known S3 and S4 systems.
#' 
#' @usage NULL
#' 
#' @section Fields:
#' \describe{
#'  \item{\code{host}}{A string giving a valid IPv4 address owned by the server, or '0.0.0.0' (the default) to listen on all addresses}
#'  \item{\code{port}}{An integer giving the port number the server should listen on (defaults to 80L)}
#'  \item{\code{refreshRate}}{The interval in seconds between run cycles when running a blocking server (defaults to 0.001)}
#'  \item{\code{triggerDir}}{A valid folder where trigger files can be put when running a blocking server (defaults to NULL)}
#' }
#' 
#' @section Methods:
#' \describe{
#'  \item{\code{ignite(block = TRUE, showcase = FALSE, ...)}}{Begins the server,either blocking the console if \code{block = TRUE} or not. If \code{showcase = TRUE} a browser window is opened directing at the server address. \code{...} will be redirected to the 'start' handler(s)}
#'  \item{\code{start(block = TRUE, showcase = FALSE, ...)}}{A less dramatic synonym of for \code{ignite}}
#'  \item{\code{reignite(block = TRUE, showcase = FALSE, ...)}}{As \code{ignite} but additionally triggers the 'resume' event after the 'start' event}
#'  \item{\code{resume(block = TRUE, showcase = FALSE, ...)}}{Another less dramatic synonym, this time for reignite}
#'  \item{\code{extinguish()}}{Stops a running server}
#'  \item{\code{stop()}}{Boring synonym for \code{extinguish}}
#'  \item{\code{on(event, handler, pos = NULL)}}{Add a handler function to to an event at the given position in the handler stack. Returns a string uniquely identifying the handler}
#'  \item{\code{off(handlerId)}}{Remove the handler tied to the given id}
#'  \item{\code{trigger(event, ...)}}{Triggers an event passing the additional arguments to the potential handlers}
#'  \item{\code{attach(plugin, ...)}}{Attaches a plugin to the server. A plugin is an R6 object with an \code{onAttach} method}
#'  \item{\code{set_data(name, value)}}{Adds data to the servers internal data store}
#'  \item{\code{get_data(name)}}{Extracts data from the internal data store}
#'  \item{\code{set_client_id_converter(converter)}}{Sets the function that converts an HTTP request into a specific client id}
#' }
#' 
#' @importFrom R6 R6Class
#' @importFrom assertthat is.string is.count is.number is.scalar has_args
#' @importFrom httpuv startServer service startDaemonizedServer stopDaemonizedServer
#' @importFrom uuid UUIDgenerate
#' @importFrom utils browseURL
#' 
#' @export
#' @docType class
#' 
#' @examples 
#' # Create a New App
#' app <- Fire$new()
#' 
Fire <- R6Class('Fire',
    public = list(
        # Methods
        initialize = function() {
            private$data <- new.env(parent = emptyenv())
            private$handlers <- new.env(parent = emptyenv())
            private$websockets <- new.env(parent = emptyenv())
            private$client_id <- function(request) {
                paste0('ID_', request$REMOTE_ADDR, '_', request$REMOTE_PORT)
            }
        },
        ignite = function(block = TRUE, showcase = FALSE, ...) {
            private$run(block = block, showcase = FALSE, ...)
        },
        start = function(block = TRUE, showcase = FALSE, ...) {
            self$ignite(block = block, showcase = FALSE, ...)
        },
        reignite = function(block = TRUE, showcase = FALSE, ...) {
            private$run(block = block, resume = TRUE, showcase = FALSE, ...)
        },
        resume = function(block = TRUE, showcase = FALSE, ...) {
            self$reignite(block = block, showcase = FALSE, ...)
        },
        extinguish = function() {
            if (private$running) {
                if (!is.null(private$server)) {
                    private$running <- FALSE
                    private$p_trigger('end', server = self)
                    stopDaemonizedServer(private$server)
                    private$server <- NULL
                } else {
                    private$quitting <- TRUE
                }
            }
        },
        stop = function() {
            self$extinguish()
        },
        on = function(event, handler, pos = NULL) {
            handlerId <- UUIDgenerate()
            private$handlerMap[[handlerId]] <- event
            private$add_handler(event, handler, pos, handlerId)
            
            handlerId
        },
        off = function(handlerId) {
            private$remove_handler(handlerId)
            private$handlerMap[[handlerId]] <- NULL
            self
        },
        trigger = function(event, ...) {
            if (event %in% private$privateTriggers) {
                warning(event, ' and other protected events cannot be triggered', call. = FALSE)
            } else {
                private$p_trigger(event, ...)
            }
            self
        },
        attach = function(plugin, ...) {
            plugin$onAttach(self, ...)
            self
        },
        set_data = function(name, value) {
            assign(name, value, envir = private$data)
            self
        },
        get_data = function(name) {
            private$data[[name]]
        },
        time = function(expr, delay, loop = FALSE) {
            stop('Timed evaluation is not yet implemented')
        },
        delay = function(expr, then) {
            stop('Delayed evaluation is not yet implemented')
        },
        async = function(expr, then) {
            stop('Asynchronous evaluation is not yet implemented')
        },
        set_client_id_converter = function(converter) {
            has_args(converter, 'request')
            private$client_id <- converter
            
            self
        }
    ),
    active = list(
        host = function(address) {
            if (missing(address)) return(private$HOST)
            is.string(address)
            is.scalar(address)
            private$HOST <- address
        },
        port = function(n) {
            if (missing(n)) return(private$PORT)
            is.count(n)
            is.scalar(n)
            private$PORT <- n
        },
        refreshRate = function(rate) {
            if (missing(rate)) return(private$REFRESHRATE)
            is.number(rate)
            is.scalar(rate)
            private$REFRESHRATE <- rate
        },
        triggerDir = function(dir) {
            if (missing(dir)) return(private$TRIGGERDIR)
            if (!is.null(dir)) {
                is.dir(dir)
            }
            private$TRIGGERDIR <- dir
        }
    ),
    private = list(
        # Data
        HOST = '0.0.0.0',
        PORT = 80,
        REFRESHRATE = 0.001,
        TRIGGERDIR = NULL,
        
        running = FALSE,
        quitting = FALSE,
        privateTriggers = c('start', 'resume', 'end', 'cycle-start', 'header', 
                            'before-request', 'request', 'after-request', 
                            'before-message', 'message', 'after-message',
                            'websocket-closed'),
        data = NULL,
        handlers = NULL,
        handlerMap = list(),
        websockets = NULL,
        client_id = NULL,
        
        
        # Methods
        run = function(block = TRUE, resume = FALSE, showcase = FALSE, ...) {
            if (!private$running) {
                private$running <- TRUE
                private$p_trigger('start', server = self, ...)
                if (resume) {
                    private$p_trigger('resume', server = self, ...)
                }
                
                if (block) {
                    on.exit({
                        private$running <- FALSE
                        private$p_trigger('end', server = self)
                    })
                    private$run_blocking_server(showcase = showcase)
                } else {
                    private$run_allowing_server(showcase = showcase)
                }
            } else {
                warning('Server is already running and cannot be started')
            }
        },
        run_blocking_server = function(showcase = FALSE) {
            server <- startServer(
                self$host, 
                self$port, 
                list(
                    call = private$request_logic,
                    onHeaders = private$header_logic,
                    onWSOpen = private$websocket_logic
                )
            )
            
            on.exit(stopServer(server))
            
            if (showcase) {
                private$open_browser()
            }
            
            while(TRUE) {
                private$p_trigger('cycle-start', server = self)
                service()
                private$external_triggers()
                private$p_trigger('cycle-end', server = self)
                if (private$quitting) {
                    private$quitting <- FALSE
                    break
                }
                Sys.sleep(self$refreshRate)
            }
        },
        run_allowing_server = function(showcase = FALSE) {
            private$server <- startDaemonizedServer(
                self$host, 
                self$port, 
                list(
                    call = private$request_logic,
                    onHeaders = private$header_logic,
                    onWSOpen = private$websocket_logic
                )
            )
            
            if (showcase) {
                private$open_browser()
            }
        },
        request_logic = function(req) {
            id <- private$client_id(req)
            args <- unlist(private$p_trigger('before-request', server = self, id = id, request = req))
            args <- modifyList(args, list(
                event = 'request',
                server = self,
                id = id,
                request = req
            ))
            response <- tail(do.call(private$p_trigger, args), 1)[[1]]
            private$p_trigger('after-request', server = self, id = id, request = req, response = response)
            response
        },
        header_logic = function(req) {
            private$p_trigger('header', server = self, id = id, request = req)
        },
        websocket_logic = function(ws) {
            id <- private$client_id(ws$request)
            assign(id, ws, envir = private$websockets)
            
            ws$onMessage(function(binary, msg) {
                args <- unlist(private$p_trigger('before-message', server = self, id = id, binary = binary, message = msg, request = ws$request))
                args <- modifyList(list(binary = binary, message = msg), args)
                args <- modifyList(args, list(
                    event = 'message',
                    server = self,
                    id = id,
                    request = ws$request
                ))
                do.call(private$p_trigger, args)
                
                private$p_trigger('after-message', server = self, id = id, binary = args$binary, message = args$message, request = ws$request)
            })
            ws$onClose(function() {
                private$p_trigger('websocket-closed', server = self, id = id, request = ws$request)
            })
        },
        add_handler = function(event, handler, pos, id) {
            if (is.null(private$handlers[[event]])) {
                private$handlers[[event]] <- HandlerStack$new()
            }
            private$handlers[[event]]$add(handler, id, pos)
        },
        remove_handler = function(id) {
            event <- private$handlerMap[[id]]
            private$handlers[[event]]$remove(id)
        },
        p_trigger = function(event, ...) {
            if (!is.null(private$handlers[[event]])) {
                private$handlers[[event]]$dispatch(...)
            } else {
                NULL
            }
        },
        external_trigger = function() {
            if (is.null(private$TRIGGERDIR)) return()
            
            triggerFiles <- list.files(private$TRIGGERDIR, pattern = '*.rds', ignore.case = TRUE, full.names = TRUE)
            while (length(triggerFiles) > 0) {
                nextFile <- order(file.info(triggerFiles)$ctime)[1]
                event <- sub('\\.rds$', '', basename(triggerFiles[nextFile]), ignore.case = TRUE)
                args <- readRDS(triggerFiles[nextFile])
                unlink(triggerFiles[nextFile])
                args$event <- event
                do.call(private$p_trigger, args)
                
                triggerFiles <- list.files(private$TRIGGERDIR, pattern = '*.rds', ignore.case = TRUE, full.names = TRUE)
            }
        },
        send_ws = function(message, id) {
            if (!is.raw(message)) {
                is.string(message)
                is.scalar(message)
            }
            private$websockets[[id]]$send(message)
        },
        close_ws = function(id) {
            private$websockets[[id]]$close()
            rm(id, envir = private$websockets)
        },
        open_browser = function() {
            url <- paste0('http://', private$HOST, ':', private$PORT, '/')
            browseURL(url)
        }
    )
)