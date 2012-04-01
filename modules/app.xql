xquery version "3.0";

module namespace app="http://exist-db.org/xquery/app";

import module namespace atomic="http://atomic.exist-db.org/xquery/atomic" at "atomic.xql";
import module namespace templates="http://exist-db.org/xquery/templates" at "templates.xql";
import module namespace config="http://exist-db.org/xquery/apps/config" at "config.xqm";
import module namespace date="http://exist-db.org/xquery/datetime" at "java:org.exist.xquery.modules.datetime.DateTimeModule";
import module namespace html2wiki="http://atomic.exist-db.org/xquery/html2wiki" at "html2wiki.xql";
import module namespace wiki="http://exist-db.org/xquery/wiki" at "java:org.exist.xquery.modules.wiki.WikiModule";

declare namespace atom="http://www.w3.org/2005/Atom";
declare namespace html="http://www.w3.org/1999/xhtml";

declare variable $app:months := ('January', 'February', 'March', 'April', 'May', 'June', 'July', 
    'August', 'September', 'October', 'November', 'December');

declare function app:feed($node as node(), $params as element(parameters)?, $model as item()*) {
    let $feed := request:get-attribute("feed")
    return
        templates:process($node/node(), $feed)
};

declare function app:breadcrumbs($node as node(), $params as element(parameters)?, $model as item()*) {
    let $collection := util:collection-name($model)
    let $path := substring-after($collection, $config:wiki-root)
    return
        <div class="breadcrumbs">
        {
            let $components := tokenize(substring($path, 2), "/")
            for $component at $p in $components
            return (
                if ($p gt 1) then
                    " / "
                else
                    (),
                <a href="{ string-join(for $i in 1 to count($components) - $p return '..', '/') }">{ $component }</a>
            )
        }
        </div>
};

declare function app:get-or-create-feed($node as node(), $params as element(parameters)?, $model as item()*) {
    let $feed := request:get-attribute("feed")
    let $data :=
        if ($feed) then
            $feed
        else
            atomic:create-feed()
    return
        templates:process($node/node(), $data)
};

declare function app:create-entry($node as node(), $params as element(parameters)?, $model as item()*) {
    let $id := request:get-parameter("id", ())
    let $published := request:get-parameter("published", current-dateTime())
    let $title := request:get-parameter("title", ())
    let $content := request:get-parameter("content", ())
    let $summary := request:get-parameter("summary", ())
    let $author := request:get-parameter("author", xmldb:get-current-user())
    let $entry :=
        <atom:entry>
            <atom:id>{$id}</atom:id>
            <atom:published>{ $published }</atom:published>
            <atom:author><atom:name>{ $author }</atom:name></atom:author>
            <atom:title>{$title}</atom:title>
            <atom:summary type="xhtml">{ wiki:parse($summary, <parameters/>) }</atom:summary>
            <atom:content type="xhtml">{ wiki:parse($content, <parameters/>) }</atom:content>
        </atom:entry>
    return
        templates:process($node/node(), $entry)
};

declare function app:entries($node as node(), $params as element(parameters)?, $feed as element(atom:feed)) {
    let $countParam := $params/param[@name = "count"]/@value
    let $id := request:get-parameter("id", ())
    let $wikiId := request:get-parameter("wiki-id", ())
    let $start := request:get-parameter("start", 1)
    let $entries :=
        for $entry in config:get-entries($feed, $id, $wikiId)
        order by xs:dateTime($entry/atom:published) descending
        return
            $entry
    let $count := if ($countParam) then number($countParam) else $config:items-per-page
    return
        element { node-name($node) } {
            $node/@*,
            for $entry in subsequence($entries, $start, $count)
            return
                templates:process($node/*[1], ($entry, count($entries))),
            templates:process($node/*[2], (count($entries), $count))
        }
};

declare function app:next-page($node as node(), $params as element(parameters)?, $model as item()*) {
    let $start := number(request:get-parameter("start", 1))
    return
        if ($start + $model[2] le $model[1]) then
            <a href="?start={$start + $model[2]}" class="next-page">{ templates:process($node/node(), $model) }</a>
        else
            ()
};

declare function app:previous-page($node as node(), $params as element(parameters)?, $model as item()*) {
    let $start := number(request:get-parameter("start", 1))
    return
        if ($start gt 1) then
            let $prev := if ($start - $model[2] gt 1) then $start - $model[2] else 1
            return
                <a href="?start={$prev}" class="prev-page">{ templates:process($node/node(), $model) }</a>
        else
            ()
};

declare function app:entry($node as node(), $params as element(parameters)?, $model as item()*) {
    let $feed := $params/param[@name = "feed"]/@value
    let $entry := $params/param[@name = "entry"]/@value
    let $collection := concat($config:wiki-root, "/", $feed)
    let $entryData := collection($collection)/atom:entry[wiki:id = $entry]
    where $entryData
    return
        templates:process($node/node(), ($entryData, 1))
};

declare function app:get-or-create-entry($node as node(), $params as element(parameters)?, $feed as element(atom:feed)) {
    let $id := request:get-parameter("id", ())
    let $wikiId := request:get-parameter("wiki-id", ())
    return
        element { node-name($node) } {
            $node/@*,
            if ($id or $wikiId) then
                let $entry := config:get-entries($feed, $id, $wikiId)
                return
                    templates:process($node/node(), ($entry, false()))
            else
                templates:process($node/node(), (atomic:create-entry(), false()))
        }
};

declare function app:title($node as node(), $params as element(parameters)?, $model as item()*) {
    let $isFeed := $model[1] instance of element(atom:feed)
    let $user := session:get-attribute("wiki.user")
    let $link :=
        if ($isFeed) then
            "."
        else if ($model[1]/wiki:id) then
            $model[1]/wiki:id/string()
        else
            concat("?id=", $model[1]/atom:id)
    return
        element { node-name($node) } {
            $node/@*,
            if ($model[1]/atom:title[@type = "xhtml"]) then
                $model[1]/atom:title/node()
            else if ($model[1]/atom:title/text()) then (
                <a href="{$link}">{$model[1]/atom:title/string()}</a>
            ) else
                <a>Untitled</a>
        }
};

declare function app:author($node as node(), $params as element(parameters)?, $model as item()*) {
    $model[1]/atom:author/atom:name/string()
};

declare function app:id($node as node(), $params as element(parameters)?, $model as item()*) {
    $model[1]/atom:id/string()
};

declare function app:publication-date-full($node as node(), $params as element(parameters)?, $model as item()*) {
    let $date := xs:dateTime($model[1]/atom:published)
    return
        datetime:format-dateTime($date, "yyyy/MM/dd 'at' HH:mm:ss z")
};

declare function app:publication-date($node as node(), $params as element(parameters)?, $model as item()*) {
    let $date := xs:dateTime($model[1]/atom:published)
    return
        <div class="date">
            <span class="month">{$app:months[month-from-dateTime($date)]}</span>
            <span class="day">{day-from-dateTime($date)}</span>
            <span class="year">{year-from-dateTime($date)}</span>
        </div>
};

declare function app:content($node as node(), $params as element(parameters)?, $model as item()*) {
    element { node-name($node) } {
        $node/@*,
        let $summary := $model[1]/atom:summary
        let $atomContent := $model[1]/atom:content
        let $content := atomic:get-content($atomContent, true())
        return (
            if ($model[2] gt 1) then
                app:process-content($atomContent/@type, ($summary, $content)[1], $model)
            else (
                if ($summary) then
                    app:process-content($summary/@type, $summary/*, $model)
                else
                    (),
                app:process-content($atomContent/@type, $content, $model)
            ),
            if ($model[2] gt 1 and $summary) then
                <a class="label" href="?id={$model[1]/atom:id}">Read article ...</a>
            else
                ()
        )
    }
};

declare function app:process-content($type as xs:string?, $content as item()?, $model as item()*) {
    app:process-content($type, $content, $model, true())
};

declare function app:process-content($type as xs:string?, $content as item()?, $model as item()*,
    $expandTemplates as xs:boolean) {
    let $type := if ($type) then $type else "html"
    return
        switch ($type)
            case "html" case "xhtml" return
                let $data := atomic:process-links($content)
                return
                    if ($expandTemplates) then
                        templates:process($data, $model)
                    else
                        $data
            default return
                $content
};

declare function app:edit-link($node as node(), $params as element(parameters)?, $model as item()*) {
    let $addParams := string-join(
        for $param in $params/param
        return
            concat($param/@name, "=", $param/@value),
        "&amp;"
    )
    return
        <a href="?id={$model[1]/atom:id}&amp;{$addParams}">{ $node/@*[local-name(.) != 'href'], $node/node() }</a>
};

declare function app:action-button($node as node(), $params as element(parameters)?, $model as item()*) {
    element { node-name($node) } {
        $node/@*,
        templates:process($node/node(), $model)
    },
    <form action="" method="post" style="display: none;">
        <input name="id" value="{$model[1]/atom:id}" type="hidden"/>
        {
            for $param in $params/param
            return
                <input name="{$param/@name}" value="{$param/@value}" type="hidden"/>
        }
    </form>
};

declare function app:edit-title($node as node(), $params as element(parameters)?, $model as item()*) {
    let $title := $model[1]/atom:title
    return
        element { node-name($node) } {
            $node/@* except $node/@value,
            if (exists($title)) then attribute value { $title } else ()
        }
};

declare function app:edit-subtitle($node as node(), $params as element(parameters)?, $model as item()*) {
    let $title := $model[1]/atom:subtitle
    return
        element { node-name($node) } {
            $node/@* except $node/@value,
            if (exists($title)) then attribute value { $title } else ()
        }
};

declare function app:edit-name($node as node(), $params as element(parameters)?, $model as item()*) {
    let $pageName := $model[1]/wiki:id
    return
        element { node-name($node) } {
            $node/@* except $node/@value,
            if ($pageName) then attribute value { $pageName } else ()
        }
};

declare function app:edit-content-type($node as node(), $params as element(parameters)?, $model as item()*) {
    let $type := $model[1]/atom:content/@type
    return
        element { node-name($node) } {
            $node/@*,
            for $option in $node/option
            return
                if ($option/@value eq $type) then
                    element { node-name($option) } {
                        $option/@*,
                        attribute selected { "selected" },
                        $option/node()
                    }
                else
                    $option
        }
};

declare function app:get-edit-mode($params as element(parameters)?) as xs:string {
    let $modeParam := $params/param[@name = "mode"]/@value/string()
    return
        if ($modeParam) then $modeParam else "markup"
};

declare function app:edit-content($node as node(), $params as element(parameters)?, $model as item()*) {
    let $mode := app:get-edit-mode($params)
    let $contentElem := $model[1]/atom:content
    let $content := atomic:get-content($contentElem, false())
    return
        element { node-name($node) } {
            $node/@*,
            if ($content instance of element()) then
                switch ($mode)
                    case "html" return
                        app:process-content($contentElem/@type, $content, $model, false())
                    default return
                        let $wiki := html2wiki:html2wiki($content)
                        let $log := util:log("WARN", ("CONTENT: ", $content, $wiki))
                        return
                            $wiki
            else
                $content
        }
};

declare function app:edit-summary($node as node(), $params as element(parameters)?, $model as item()*) {
    let $mode := app:get-edit-mode($params)
    let $summary := $model[1]/atom:summary
    let $summaryContent := $summary/*
    return
        element { node-name($node) } {
            $node/@*,
            switch ($mode)
                case "html" return
                    app:process-content($summary/@type, $summaryContent, $model, false())
                default return
                    html2wiki:html2wiki($summaryContent)
        }
};

declare function app:edit-publication-date($node as node(), $params as element(parameters)?, $model as item()*) {
    element { node-name($node) } {
        $node/@*,
        attribute value { $model[1]/atom:published }
    }
};

declare function app:edit-author($node as node(), $params as element(parameters)?, $model as item()*) {
    element { node-name($node) } {
        $node/@*,
        attribute value { $model[1]/atom:author }
    }
};

declare function app:edit-id($node as node(), $params as element(parameters)?, $model as item()*) {
    element { node-name($node) } {
        $node/@*,
        attribute value { $model[1]/atom:id }
    }
};

declare function app:edit-external($node as node(), $params as element(parameters)?, $model as item()*) {
    element { node-name($node) } {
        $node/@*,
        if (empty($model[1]/atom:content) or $model[1]/atom:content/@src) then
            attribute checked { "checked" }
        else
            ()
    }
};

declare function app:edit-collection($node as node(), $params as element(parameters)?, $model as item()*) {
    let $collection := request:get-attribute("collection")
    let $feed :=
        if ($collection) then 
            $collection
        else
            util:collection-name(request:get-attribute("feed"))
    return
        element { node-name($node) } {
            $node/@*,
            attribute value { $feed }
        }
};

declare function app:edit-resource($node as node(), $params as element(parameters)?, $model as item()*) {
    element { node-name($node) } {
        $node/@*,
        attribute value { util:document-name($model[1]) }
    }
};

declare function app:edit-editor($node as node(), $params as element(parameters)?, $model as item()*) {
    element { node-name($node) } {
        $node/@*,
        attribute value { $model[1]/wiki:editor/string() }
    }
};

declare function app:login($node as node(), $params as element(parameters)?, $model as item()*) {
    let $user := session:get-attribute("wiki.user")
    return
        if ($user) then
            templates:process($node/*[2], $model)
        else
            templates:process($node/*[1], $model)
};

declare function app:user($node as node(), $params as element(parameters)?, $model as item()*) {
    element { node-name($node) } {
        session:get-attribute("wiki.user")
    }
};

declare function app:home-link($node as node(), $params as element(parameters)?, $model as item()*) {
    <a href="{$config:app-home}">{ $node/@*, templates:process($node/node(), $model)}</a>
};