--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: hstore; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS hstore WITH SCHEMA public;


--
-- Name: EXTENSION hstore; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION hstore IS 'data type for storing sets of (key, value) pairs';


SET search_path = public, pg_catalog;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: actions; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE actions (
    id integer NOT NULL,
    user_id integer,
    query text,
    actions text[] DEFAULT '{}'::text[],
    feed_ids text[] DEFAULT '{}'::text[],
    all_feeds boolean DEFAULT false,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: actions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE actions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: actions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE actions_id_seq OWNED BY actions.id;


--
-- Name: billing_events; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE billing_events (
    id integer NOT NULL,
    details text,
    event_type character varying(255),
    billable_id integer,
    billable_type character varying(255),
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    event_id character varying(255)
);


--
-- Name: billing_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE billing_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: billing_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE billing_events_id_seq OWNED BY billing_events.id;


--
-- Name: coupons; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE coupons (
    id integer NOT NULL,
    user_id integer,
    coupon_code character varying(255),
    sent_to character varying(255),
    redeemed boolean DEFAULT false,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: coupons_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE coupons_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: coupons_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE coupons_id_seq OWNED BY coupons.id;


--
-- Name: entries; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE entries (
    id integer NOT NULL,
    feed_id integer,
    title text,
    url text,
    author text,
    summary text,
    content text,
    published timestamp without time zone,
    updated timestamp without time zone,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    entry_id text,
    public_id character varying(255),
    old_public_id character varying(255),
    starred_entries_count integer DEFAULT 0 NOT NULL,
    data json
);


--
-- Name: entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE entries_id_seq OWNED BY entries.id;


--
-- Name: feeds; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE feeds (
    id integer NOT NULL,
    title text,
    feed_url text,
    site_url text,
    etag text,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    last_modified timestamp without time zone,
    subscriptions_count integer DEFAULT 0 NOT NULL,
    protected boolean DEFAULT false
);


--
-- Name: feeds_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE feeds_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: feeds_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE feeds_id_seq OWNED BY feeds.id;


--
-- Name: import_items; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE import_items (
    id integer NOT NULL,
    import_id integer,
    details text,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    item_type character varying(255)
);


--
-- Name: import_items_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE import_items_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: import_items_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE import_items_id_seq OWNED BY import_items.id;


--
-- Name: imports; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE imports (
    id integer NOT NULL,
    user_id integer,
    complete boolean DEFAULT false,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    upload character varying(255)
);


--
-- Name: imports_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE imports_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: imports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE imports_id_seq OWNED BY imports.id;


--
-- Name: plans; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE plans (
    id integer NOT NULL,
    stripe_id character varying(255),
    name character varying(255),
    price numeric,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    price_tier integer
);


--
-- Name: plans_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE plans_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: plans_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE plans_id_seq OWNED BY plans.id;


--
-- Name: saved_searches; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE saved_searches (
    id integer NOT NULL,
    user_id integer NOT NULL,
    name text NOT NULL,
    query text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: saved_searches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE saved_searches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: saved_searches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE saved_searches_id_seq OWNED BY saved_searches.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE schema_migrations (
    version character varying(255) NOT NULL
);


--
-- Name: sharing_services; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE sharing_services (
    id integer NOT NULL,
    user_id integer,
    label text,
    url text,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: sharing_services_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE sharing_services_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sharing_services_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE sharing_services_id_seq OWNED BY sharing_services.id;


--
-- Name: starred_entries; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE starred_entries (
    id integer NOT NULL,
    user_id integer,
    feed_id integer,
    entry_id integer,
    published timestamp without time zone,
    created_at timestamp without time zone,
    updated_at timestamp without time zone
);


--
-- Name: starred_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE starred_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: starred_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE starred_entries_id_seq OWNED BY starred_entries.id;


--
-- Name: subscriptions; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE subscriptions (
    id integer NOT NULL,
    user_id integer,
    feed_id integer,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    title text,
    view_inline boolean DEFAULT false,
    active boolean DEFAULT true,
    push boolean DEFAULT false
);


--
-- Name: subscriptions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE subscriptions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: subscriptions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE subscriptions_id_seq OWNED BY subscriptions.id;


--
-- Name: taggings; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE taggings (
    id integer NOT NULL,
    feed_id integer,
    user_id integer,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    tag_id integer
);


--
-- Name: taggings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE taggings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: taggings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE taggings_id_seq OWNED BY taggings.id;


--
-- Name: tags; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE tags (
    id integer NOT NULL,
    name character varying(255),
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL
);


--
-- Name: tags_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE tags_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tags_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE tags_id_seq OWNED BY tags.id;


--
-- Name: unread_entries; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE unread_entries (
    id integer NOT NULL,
    user_id integer,
    feed_id integer,
    entry_id integer,
    published timestamp without time zone,
    created_at timestamp without time zone,
    updated_at timestamp without time zone,
    entry_created_at timestamp without time zone
);


--
-- Name: unread_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE unread_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: unread_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE unread_entries_id_seq OWNED BY unread_entries.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE users (
    id integer NOT NULL,
    email character varying(255),
    password_digest character varying(255),
    customer_id character varying(255),
    last_4_digits character varying(255),
    plan_id integer,
    admin boolean DEFAULT false,
    suspended boolean DEFAULT false,
    created_at timestamp without time zone NOT NULL,
    updated_at timestamp without time zone NOT NULL,
    auth_token character varying(255),
    password_reset_token character varying(255),
    password_reset_sent_at timestamp without time zone,
    settings hstore,
    starred_token character varying(255),
    inbound_email_token character varying(255)
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE users_id_seq OWNED BY users.id;


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY actions ALTER COLUMN id SET DEFAULT nextval('actions_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY billing_events ALTER COLUMN id SET DEFAULT nextval('billing_events_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY coupons ALTER COLUMN id SET DEFAULT nextval('coupons_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY entries ALTER COLUMN id SET DEFAULT nextval('entries_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY feeds ALTER COLUMN id SET DEFAULT nextval('feeds_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY import_items ALTER COLUMN id SET DEFAULT nextval('import_items_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY imports ALTER COLUMN id SET DEFAULT nextval('imports_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY plans ALTER COLUMN id SET DEFAULT nextval('plans_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY saved_searches ALTER COLUMN id SET DEFAULT nextval('saved_searches_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY sharing_services ALTER COLUMN id SET DEFAULT nextval('sharing_services_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY starred_entries ALTER COLUMN id SET DEFAULT nextval('starred_entries_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY subscriptions ALTER COLUMN id SET DEFAULT nextval('subscriptions_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY taggings ALTER COLUMN id SET DEFAULT nextval('taggings_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY tags ALTER COLUMN id SET DEFAULT nextval('tags_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY unread_entries ALTER COLUMN id SET DEFAULT nextval('unread_entries_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY users ALTER COLUMN id SET DEFAULT nextval('users_id_seq'::regclass);


--
-- Name: actions_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY actions
    ADD CONSTRAINT actions_pkey PRIMARY KEY (id);


--
-- Name: billing_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY billing_events
    ADD CONSTRAINT billing_events_pkey PRIMARY KEY (id);


--
-- Name: coupons_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY coupons
    ADD CONSTRAINT coupons_pkey PRIMARY KEY (id);


--
-- Name: entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY entries
    ADD CONSTRAINT entries_pkey PRIMARY KEY (id);


--
-- Name: feeds_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY feeds
    ADD CONSTRAINT feeds_pkey PRIMARY KEY (id);


--
-- Name: import_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY import_items
    ADD CONSTRAINT import_items_pkey PRIMARY KEY (id);


--
-- Name: imports_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY imports
    ADD CONSTRAINT imports_pkey PRIMARY KEY (id);


--
-- Name: plans_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY plans
    ADD CONSTRAINT plans_pkey PRIMARY KEY (id);


--
-- Name: saved_searches_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY saved_searches
    ADD CONSTRAINT saved_searches_pkey PRIMARY KEY (id);


--
-- Name: sharing_services_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY sharing_services
    ADD CONSTRAINT sharing_services_pkey PRIMARY KEY (id);


--
-- Name: starred_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY starred_entries
    ADD CONSTRAINT starred_entries_pkey PRIMARY KEY (id);


--
-- Name: subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id);


--
-- Name: taggings_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY taggings
    ADD CONSTRAINT taggings_pkey PRIMARY KEY (id);


--
-- Name: tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY tags
    ADD CONSTRAINT tags_pkey PRIMARY KEY (id);


--
-- Name: unread_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY unread_entries
    ADD CONSTRAINT unread_entries_pkey PRIMARY KEY (id);


--
-- Name: users_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: index_actions_on_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_actions_on_user_id ON actions USING btree (user_id);


--
-- Name: index_billing_events_on_billable_id_and_billable_type; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_billing_events_on_billable_id_and_billable_type ON billing_events USING btree (billable_id, billable_type);


--
-- Name: index_billing_events_on_event_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_billing_events_on_event_id ON billing_events USING btree (event_id);


--
-- Name: index_coupons_on_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_coupons_on_user_id ON coupons USING btree (user_id);


--
-- Name: index_entries_on_feed_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_entries_on_feed_id ON entries USING btree (feed_id);


--
-- Name: index_entries_on_public_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_entries_on_public_id ON entries USING btree (public_id);


--
-- Name: index_feeds_on_feed_url; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_feeds_on_feed_url ON feeds USING btree (feed_url);


--
-- Name: index_import_items_on_import_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_import_items_on_import_id ON import_items USING btree (import_id);


--
-- Name: index_saved_searches_on_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_saved_searches_on_user_id ON saved_searches USING btree (user_id);


--
-- Name: index_sharing_services_on_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_sharing_services_on_user_id ON sharing_services USING btree (user_id);


--
-- Name: index_starred_entries_on_entry_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_starred_entries_on_entry_id ON starred_entries USING btree (entry_id);


--
-- Name: index_starred_entries_on_feed_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_starred_entries_on_feed_id ON starred_entries USING btree (feed_id);


--
-- Name: index_starred_entries_on_published; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_starred_entries_on_published ON starred_entries USING btree (published);


--
-- Name: index_starred_entries_on_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_starred_entries_on_user_id ON starred_entries USING btree (user_id);


--
-- Name: index_starred_entries_on_user_id_and_entry_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_starred_entries_on_user_id_and_entry_id ON starred_entries USING btree (user_id, entry_id);


--
-- Name: index_subscriptions_on_created_at; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_subscriptions_on_created_at ON subscriptions USING btree (created_at);


--
-- Name: index_subscriptions_on_feed_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_subscriptions_on_feed_id ON subscriptions USING btree (feed_id);


--
-- Name: index_subscriptions_on_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_subscriptions_on_user_id ON subscriptions USING btree (user_id);


--
-- Name: index_subscriptions_on_user_id_and_feed_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_subscriptions_on_user_id_and_feed_id ON subscriptions USING btree (user_id, feed_id);


--
-- Name: index_taggings_on_tag_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_taggings_on_tag_id ON taggings USING btree (tag_id);


--
-- Name: index_taggings_on_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_taggings_on_user_id ON taggings USING btree (user_id);


--
-- Name: index_taggings_on_user_id_and_feed_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_taggings_on_user_id_and_feed_id ON taggings USING btree (user_id, feed_id);


--
-- Name: index_taggings_on_user_id_and_tag_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_taggings_on_user_id_and_tag_id ON taggings USING btree (user_id, tag_id);


--
-- Name: index_tags_on_name; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_tags_on_name ON tags USING btree (name);


--
-- Name: index_unread_entries_on_entry_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_unread_entries_on_entry_id ON unread_entries USING btree (entry_id);


--
-- Name: index_unread_entries_on_feed_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_unread_entries_on_feed_id ON unread_entries USING btree (feed_id);


--
-- Name: index_unread_entries_on_user_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_unread_entries_on_user_id ON unread_entries USING btree (user_id);


--
-- Name: index_unread_entries_on_user_id_and_entry_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_unread_entries_on_user_id_and_entry_id ON unread_entries USING btree (user_id, entry_id);


--
-- Name: index_unread_entries_on_user_id_and_feed_id_and_published; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_unread_entries_on_user_id_and_feed_id_and_published ON unread_entries USING btree (user_id, feed_id, published);


--
-- Name: index_unread_entries_on_user_id_and_published; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE INDEX index_unread_entries_on_user_id_and_published ON unread_entries USING btree (user_id, published);


--
-- Name: index_users_on_auth_token; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_users_on_auth_token ON users USING btree (auth_token);


--
-- Name: index_users_on_customer_id; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_users_on_customer_id ON users USING btree (customer_id);


--
-- Name: index_users_on_inbound_email_token; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_users_on_inbound_email_token ON users USING btree (inbound_email_token);


--
-- Name: index_users_on_lower_email; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_users_on_lower_email ON users USING btree (lower((email)::text));


--
-- Name: index_users_on_password_reset_token; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_users_on_password_reset_token ON users USING btree (password_reset_token);


--
-- Name: index_users_on_starred_token; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX index_users_on_starred_token ON users USING btree (starred_token);


--
-- Name: unique_schema_migrations; Type: INDEX; Schema: public; Owner: -; Tablespace: 
--

CREATE UNIQUE INDEX unique_schema_migrations ON schema_migrations USING btree (version);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user",public;

INSERT INTO schema_migrations (version) VALUES ('20121010042043');

INSERT INTO schema_migrations (version) VALUES ('20121011035904');

INSERT INTO schema_migrations (version) VALUES ('20121011035933');

INSERT INTO schema_migrations (version) VALUES ('20121012074155');

INSERT INTO schema_migrations (version) VALUES ('20121012075009');

INSERT INTO schema_migrations (version) VALUES ('20121013082327');

INSERT INTO schema_migrations (version) VALUES ('20121019045613');

INSERT INTO schema_migrations (version) VALUES ('20121019150248');

INSERT INTO schema_migrations (version) VALUES ('20121019231945');

INSERT INTO schema_migrations (version) VALUES ('20121023224542');

INSERT INTO schema_migrations (version) VALUES ('20121029015723');

INSERT INTO schema_migrations (version) VALUES ('20121106123418');

INSERT INTO schema_migrations (version) VALUES ('20121109200937');

INSERT INTO schema_migrations (version) VALUES ('20121115044716');

INSERT INTO schema_migrations (version) VALUES ('20121117212752');

INSERT INTO schema_migrations (version) VALUES ('20121117225703');

INSERT INTO schema_migrations (version) VALUES ('20121124070158');

INSERT INTO schema_migrations (version) VALUES ('20121124070242');

INSERT INTO schema_migrations (version) VALUES ('20121125043913');

INSERT INTO schema_migrations (version) VALUES ('20121125051935');

INSERT INTO schema_migrations (version) VALUES ('20121202173023');

INSERT INTO schema_migrations (version) VALUES ('20121220043916');

INSERT INTO schema_migrations (version) VALUES ('20121220044158');

INSERT INTO schema_migrations (version) VALUES ('20130101205608');

INSERT INTO schema_migrations (version) VALUES ('20130107050848');

INSERT INTO schema_migrations (version) VALUES ('20130108022157');

INSERT INTO schema_migrations (version) VALUES ('20130121161637');

INSERT INTO schema_migrations (version) VALUES ('20130121162410');

INSERT INTO schema_migrations (version) VALUES ('20130121162825');

INSERT INTO schema_migrations (version) VALUES ('20130124120921');

INSERT INTO schema_migrations (version) VALUES ('20130124141157');

INSERT INTO schema_migrations (version) VALUES ('20130124144546');

INSERT INTO schema_migrations (version) VALUES ('20130124151206');

INSERT INTO schema_migrations (version) VALUES ('20130126044222');

INSERT INTO schema_migrations (version) VALUES ('20130202145544');

INSERT INTO schema_migrations (version) VALUES ('20130203182936');

INSERT INTO schema_migrations (version) VALUES ('20130203185241');

INSERT INTO schema_migrations (version) VALUES ('20130204000143');

INSERT INTO schema_migrations (version) VALUES ('20130218220024');

INSERT INTO schema_migrations (version) VALUES ('20130218221354');

INSERT INTO schema_migrations (version) VALUES ('20130226190942');

INSERT INTO schema_migrations (version) VALUES ('20130226191831');

INSERT INTO schema_migrations (version) VALUES ('20130227065820');

INSERT INTO schema_migrations (version) VALUES ('20130228150343');

INSERT INTO schema_migrations (version) VALUES ('20130228151024');

INSERT INTO schema_migrations (version) VALUES ('20130301095638');

INSERT INTO schema_migrations (version) VALUES ('20130302033514');

INSERT INTO schema_migrations (version) VALUES ('20130326034638');

INSERT INTO schema_migrations (version) VALUES ('20130327174832');

INSERT INTO schema_migrations (version) VALUES ('20130403032020');

INSERT INTO schema_migrations (version) VALUES ('20130403032414');

INSERT INTO schema_migrations (version) VALUES ('20130403032846');

INSERT INTO schema_migrations (version) VALUES ('20130407192646');

INSERT INTO schema_migrations (version) VALUES ('20130408045541');

INSERT INTO schema_migrations (version) VALUES ('20130420122821');

INSERT INTO schema_migrations (version) VALUES ('20130420171308');

INSERT INTO schema_migrations (version) VALUES ('20130420171357');

INSERT INTO schema_migrations (version) VALUES ('20130424132435');

INSERT INTO schema_migrations (version) VALUES ('20130429063608');

INSERT INTO schema_migrations (version) VALUES ('20130429152153');

INSERT INTO schema_migrations (version) VALUES ('20130429154717');

INSERT INTO schema_migrations (version) VALUES ('20130508034554');

INSERT INTO schema_migrations (version) VALUES ('20130514072924');

INSERT INTO schema_migrations (version) VALUES ('20130515203825');

INSERT INTO schema_migrations (version) VALUES ('20130517164043');

INSERT INTO schema_migrations (version) VALUES ('20130520012402');

INSERT INTO schema_migrations (version) VALUES ('20130531231556');

INSERT INTO schema_migrations (version) VALUES ('20130616023624');

INSERT INTO schema_migrations (version) VALUES ('20130616031049');

INSERT INTO schema_migrations (version) VALUES ('20130619222820');

INSERT INTO schema_migrations (version) VALUES ('20130701042440');

INSERT INTO schema_migrations (version) VALUES ('20130709054041');

INSERT INTO schema_migrations (version) VALUES ('20130713170339');

INSERT INTO schema_migrations (version) VALUES ('20130720194025');

INSERT INTO schema_migrations (version) VALUES ('20130730090745');

INSERT INTO schema_migrations (version) VALUES ('20130731234248');

INSERT INTO schema_migrations (version) VALUES ('20130801194304');

INSERT INTO schema_migrations (version) VALUES ('20130820123435');

INSERT INTO schema_migrations (version) VALUES ('20130826053351');

INSERT INTO schema_migrations (version) VALUES ('20131011204115');

INSERT INTO schema_migrations (version) VALUES ('20131017013531');

INSERT INTO schema_migrations (version) VALUES ('20131024055750');

INSERT INTO schema_migrations (version) VALUES ('20131025172652');

INSERT INTO schema_migrations (version) VALUES ('20131101024758');

INSERT INTO schema_migrations (version) VALUES ('20131101063139');

INSERT INTO schema_migrations (version) VALUES ('20131105035905');

INSERT INTO schema_migrations (version) VALUES ('20131106060451');
