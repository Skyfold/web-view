module Web.UI.Types where

import Data.Aeson
import Data.Map (Map)
import Data.Map.Strict qualified as M
import Data.String (IsString (..))
import Data.Text (Text, pack, unpack)
import Data.Text qualified as T
import Effectful
import Effectful.Reader.Static
import Effectful.State.Static.Local as ES
import GHC.Generics (Generic)


-- import Data.Text.Lazy qualified as L

type Name = Text
type AttValue = Text


type Attribute = (Name, AttValue)
type Attributes = Map Name AttValue


type Styles = Map Name StyleValue


data Class = Class
  { selector :: Selector
  , properties :: Styles
  }


instance ToJSON Class where
  toJSON c = toJSON c.selector


data Selector = Selector
  { parent :: Maybe Text
  , pseudo :: Maybe Pseudo
  , className :: ClassName
  }
  deriving (Eq, Ord, Generic, ToJSON)


instance IsString Selector where
  fromString s = Selector Nothing Nothing (fromString s)


selectorAddPseudo :: Pseudo -> Selector -> Selector
selectorAddPseudo ps (Selector pr _ cn) = Selector pr (Just ps) cn


selectorAddParent :: Text -> Selector -> Selector
selectorAddParent p (Selector _ ps c) = Selector (Just p) ps c


selector :: ClassName -> Selector
selector = Selector Nothing Nothing


selectorText :: Selector -> T.Text
selectorText s =
  parent s.parent <> "." <> addPseudo s.pseudo (classNameElementText s.parent Nothing s.className)
 where
  parent Nothing = ""
  parent (Just p) = "." <> p <> " "

  addPseudo Nothing c = c
  addPseudo (Just p) c =
    pseudoText p <> "\\:" <> c <> ":" <> pseudoText p


newtype ClassName = ClassName
  { text :: Text
  }
  deriving newtype (Eq, Ord, IsString, ToJSON)


-- | The class name as it appears in the element
classNameElementText :: Maybe Text -> Maybe Pseudo -> ClassName -> Text
classNameElementText mp mps c =
  addPseudo mps . addParent mp $ c.text
 where
  addParent Nothing cn = cn
  addParent (Just p) cn = p <> "-" <> cn

  addPseudo :: Maybe Pseudo -> Text -> Text
  addPseudo Nothing cn = cn
  addPseudo (Just p) cn =
    pseudoText p <> ":" <> cn


pseudoText :: Pseudo -> Text
pseudoText p = T.toLower $ pack $ show p


data Pseudo
  = Hover
  | Active
  deriving (Show, Eq, Ord, Generic, ToJSON)


data StyleValue
  = Px Int
  | Rem Float
  | Hex HexColor
  | RGB String
  | Value String


instance IsString StyleValue where
  fromString = Value


instance Show StyleValue where
  show (Value s) = s
  show (Px n) = show n <> "px"
  show (Rem s) = show s <> "rem"
  show (Hex (HexColor s)) = "#" <> unpack (T.dropWhile (== '#') s)
  -- it needs to have a string?
  -- this might need to get more complicated
  show (RGB s) = "rgb(" <> s <> ")"


newtype HexColor = HexColor Text


instance IsString HexColor where
  fromString = HexColor . T.dropWhile (== '#') . T.pack


attribute :: Name -> AttValue -> Attribute
attribute n v = (n, v)


data Element = Element
  { name :: Name
  , classes :: [[Class]]
  , attributes :: Attributes
  , children :: [Content]
  }


-- optimized for size, [name, atts, [children]]
instance ToJSON Element where
  toJSON el =
    Array
      [ String el.name
      , toJSON $ flatAttributes el
      , toJSON el.children
      ]


data Content
  = Node Element
  | Text Text


instance ToJSON Content where
  toJSON (Node el) = toJSON el
  toJSON (Text t) = String t


{- | Views contain their contents, and a list of all styles mentioned during their rendering
newtype View a = View (State ViewState a)
  deriving newtype (Functor, Applicative, Monad, MonadState ViewState)
-}
data ViewState = ViewState
  { contents :: [Content]
  , css :: Map Selector Class
  }


instance Semigroup ViewState where
  va <> vb = ViewState (va.contents <> vb.contents) (va.css <> vb.css)


newtype View ctx a = View {viewState :: Eff [Reader ctx, State ViewState] a}
  deriving newtype (Functor, Applicative, Monad)


instance IsString (View ctx ()) where
  fromString s = modContents (const [Text (pack s)])


runView :: ctx -> View ctx () -> ViewState
runView ctx (View ef) =
  runPureEff . execState (ViewState [] []) . runReader ctx $ ef


-- | A function that modifies an element. Allows for easy chaining and composition
type Mod = Element -> Element


modContents :: ([Content] -> [Content]) -> View c ()
modContents f = View $ do
  ES.modify $ \s -> s{contents = f s.contents}


modCss :: (Map Selector Class -> Map Selector Class) -> View c ()
modCss f = View $ do
  ES.modify $ \s -> s{css = f s.css}


context :: View c c
context = View ask


-- we want to convert an existing view to a new context, discarding the old one
addContext :: cx -> View cx () -> View c ()
addContext ctx vw = do
  -- runs the sub-view in a different context, saving its state
  -- we need to MERGE it
  let st = runView ctx vw
  View $ ES.modify $ \s -> s <> st


mapRoot :: Mod -> View c ()
mapRoot f = modContents mapContents
 where
  mapContents (Node root : cts) = Node (f root) : cts
  mapContents cts = cts


data TRBL a = TRBL
  { top :: a
  , right :: a
  , bottom :: a
  , left :: a
  }


-- | Attributes that include classes
newtype FlatAttributes = FlatAttributes {attributes :: Attributes}
  deriving (Generic)
  deriving newtype (ToJSON)


flatAttributes :: Element -> FlatAttributes
flatAttributes t =
  FlatAttributes
    $ addClass (mconcat t.classes) t.attributes
 where
  addClass [] atts = atts
  addClass cx atts = M.insert "class" (classAttValue cx) atts

  classAttValue :: [Class] -> T.Text
  classAttValue cx =
    T.intercalate " " $ fmap (\c -> classNameElementText c.selector.parent c.selector.pseudo c.selector.className) cx
