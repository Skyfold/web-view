{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE QuasiQuotes #-}

module Web.Hyperbole.Sockets where

import Control.Monad (forever)
import Data.Aeson (ToJSON)
import Data.Aeson qualified as A
import Data.ByteString.Lazy qualified as BL
import Data.String.Conversions (cs)
import Data.String.Interpolate (i)
import Data.Text (Text)
import Effectful
import Effectful.Dispatch.Dynamic
import Effectful.State.Static.Local
import Network.WebSockets (Connection, ConnectionOptions, ServerApp, WebSocketsData)
import Network.WebSockets qualified as WS
import Web.UI

data Command
  = VDOM [Content]
  | Test Text

data Socket :: Effect where
  SendMessage :: BL.ByteString -> Socket m ()
  ReceiveData :: (WebSocketsData a) => Socket m a

type instance DispatchOf Socket = 'Dynamic

-- we should assume a connection here?
-- Accept :: PendingConnection -> Sockets m Connection

data Client = Client
  { counter :: Int
  , contents :: [Content]
  }

type instance DispatchOf Socket = 'Dynamic

connectionOptions :: ConnectionOptions
connectionOptions = WS.defaultConnectionOptions

socketApplication :: Eff [Socket, IOE] () -> ServerApp
socketApplication talk pending = do
  conn <- WS.acceptRequest pending
  -- WS.sendTextData conn ("HELLO CLIENT" :: Text)
  let client = Client 0 []
  runEff . runSocket conn client $ forever talk

runSocket
  :: (IOE :> es)
  => Connection
  -> Client
  -> Eff (Socket : es) a
  -> Eff es a
runSocket conn client = reinterpret (evalState client) $ \_ -> \case
  SendMessage t -> do
    -- cl :: Client <- get
    liftIO $ WS.sendTextData conn t
  ReceiveData -> do
    a <- liftIO $ WS.receiveData conn
    modify $ \c -> c{counter = c.counter + 1}
    pure a

sendCommand :: (Socket :> es) => Command -> Eff es ()
sendCommand (VDOM cnt) = send $ SendMessage (formatMessage "VDOM" cnt)
sendCommand (Test cnt) = send $ SendMessage (formatMessage "Test" cnt)

receiveData :: (Socket :> es, WebSocketsData a) => Eff es a
receiveData = send ReceiveData

formatMessage :: (ToJSON a) => BL.ByteString -> a -> BL.ByteString
formatMessage flag cnt =
  let content = A.encode cnt
   in [i|#{flag} #{content}|]
