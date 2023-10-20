{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes #-}

module Web.UI.Render where

import Data.ByteString.Lazy qualified as BL
import Data.Function ((&))
import Data.Map (Map)
import Data.Map qualified as M
import Data.String.Interpolate (i)
import Data.Text qualified as T
import Data.Text.Lazy (Text)
import Data.Text.Lazy qualified as L
import Data.Text.Lazy.Encoding qualified as L
import Web.UI.Element (insertContents)

-- import Debug.Trace
import Web.UI.Types


type Indent = Int


htmlTag :: ([Text] -> [Text]) -> Element -> [Text]
htmlTag ind tag =
  case tag.children of
    [] ->
      -- autoClosing creates a bug in chrome. An auto-closed div
      -- absorbs the next children
      [open <> htmlAtts (flatAttributes tag) <> ">" <> close]
    -- single text node
    [Text t] ->
      -- SINGLE text node, just display it indented
      [open <> htmlAtts (flatAttributes tag) <> ">" <> L.fromStrict t <> close]
    _ ->
      mconcat
        [ [open <> htmlAtts (flatAttributes tag) <> ">"]
        , ind $ htmlChildren tag.children
        , [close]
        ]
 where
  open = "<" <> L.fromStrict tag.name
  close = "</" <> L.fromStrict tag.name <> ">"

  htmlContent :: Content -> [Text]
  htmlContent (Node t) = htmlTag ind t
  htmlContent (Text t) = [L.fromStrict t]
  htmlContent (Raw t) = [L.fromStrict t]

  htmlChildren :: [Content] -> [Text]
  htmlChildren cts =
    mconcat
      $ fmap htmlContent cts

  htmlAtts :: FlatAttributes -> Text
  htmlAtts (FlatAttributes []) = ""
  htmlAtts (FlatAttributes as) =
    " "
      <> L.intercalate " " (map htmlAtt $ M.toList as)
   where
    htmlAtt (k, v) =
      L.fromStrict $ k <> "=" <> "'" <> v <> "'"


indentation :: Text
indentation = "  "


indentAll :: [Text] -> [Text]
indentAll = fmap indent


indent :: Text -> Text
indent t = indentation <> t


noIndent :: Indent -> [Text] -> [Text]
noIndent _ ts = ts


renderLazyText :: forall c. c -> View c () -> Text
renderLazyText c u = L.intercalate "\n" content
 where
  -- T.intercalate "\n" (content <> style css)
  content :: [Text]
  content = map renderContent $ (.contents) $ runView c addCss

  addCss :: View c ()
  addCss = do
    insertContents [styleElement]
    u

  css :: [T.Text]
  css = renderCSS $ (.css) $ runView c u

  styleElement :: Content
  styleElement =
    Node $ Element "style" [] [("type", "text/css")] [Text $ T.intercalate "\n" css]


renderText :: c -> View c () -> T.Text
renderText c = L.toStrict . renderLazyText c


renderLazyByteString :: c -> View c () -> BL.ByteString
renderLazyByteString c = L.encodeUtf8 . renderLazyText c


renderContent :: Content -> Text
renderContent (Node d) = L.unlines $ htmlTag indentAll d
renderContent (Text t) = L.fromStrict t
renderContent (Raw t) = L.fromStrict t


renderCSS :: Map Selector Class -> [T.Text]
renderCSS = map renderClass . M.elems
 where
  renderClass :: Class -> T.Text
  renderClass c =
    let sel = selectorText c.selector
        props = T.intercalate "; " (map renderProp $ M.toList c.properties)
     in [i|#{sel} { #{props} }|] & addMedia c.selector.media

  addMedia Nothing css = css
  addMedia (Just m) css =
    let mc = mediaCriteria m
     in [i|@media #{mc} { #{css} }|]

  mediaCriteria :: Media -> Text
  mediaCriteria (MinWidth n) = let v = Px n in [i|(min-width: #{v})|]
  mediaCriteria (MaxWidth n) = let v = Px n in [i|(max-width: #{v})|]

  renderProp :: (T.Text, StyleValue) -> T.Text
  renderProp (p, cv) = p <> ":" <> renderStyle cv


renderStyle :: StyleValue -> T.Text
renderStyle v = T.pack $ show v


showView :: c -> View c () -> Text
showView c v =
  let st = runView c v
   in L.unlines $ mconcat $ map showContent st.contents


showContent :: Content -> [Text]
showContent (Node t) = htmlTag indentAll t
showContent (Text t) = [L.fromStrict t]
showContent (Raw t) = [L.fromStrict t]
