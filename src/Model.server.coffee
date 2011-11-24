transaction = require './transaction'
BrowserModel = require './Model'
Promise = require './Promise'

module.exports = ServerModel = ->
  self = this
  BrowserModel.apply self, arguments
  self.clientIdPromise = (new Promise).on (clientId) ->
    self._clientId = clientId
  return

ServerModel:: = Object.create BrowserModel::

# Update Model's prototype to provide server-side functionality

ServerModel::_baseOnTxn = ServerModel::_onTxn
ServerModel::_onTxn = (txn) ->
  self = this
  @clientIdPromise.on (clientId) ->
    self.store._nextTxnNum clientId, (num) ->
      self._txnNum = num
      self._baseOnTxn txn, num

ServerModel::_commit = (txn) ->
  self = this
  @store._commit txn, (err, txn) ->
    return self._removeTxn transaction.id txn if err
    self._onTxn txn

ServerModel::bundle = (callback) ->
  self = this
  # Wait for all pending transactions to complete before returning
  return setTimeout (-> self.bundle callback), 10  if @_txnQueue.length
  Promise.parallel(@clientIdPromise, @startIdPromise).on ->
    self._bundle callback

ServerModel::_bundle = (callback) ->
  # Unsubscribe the model from PubSub events. It will be resubscribed again
  # when the model connects over socket.io
  clientId = @_clientId
  @store._pubSub.unsubscribe clientId
  delete @store._localModels[clientId]

  otFields = {}
  for path, field of @otFields
    # OT objects aren't serializable until after one or more OT operations
    # have occured on that object
    otFields[path] = field.toJSON()  if field.toJSON
  
  callback JSON.stringify
    data: @get()
    otFields: otFields
    base: @_adapter.version()
    clientId: clientId
    storeSubs: @_storeSubs
    startId: @_startId
    txnCount: @_txnCount
    txnNum: @_txnNum
    ioUri: @_ioUri

ServerModel::_addSub = (paths, callback) ->
  store = @store
  self = this
  @clientIdPromise.on (clientId) ->
    # Subscribe while the model still only resides on the server
    # The model is unsubscribed before sending to the browser
    store._pubSub.subscribe clientId, paths
    store._localModels[clientId] = self

    store._fetchSubData paths, (err, data, otData) ->
      self._initSubData data
      self._initSubOtData otData
      callback()
