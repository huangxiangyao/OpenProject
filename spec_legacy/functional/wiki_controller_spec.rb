#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) 2012-2022 the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++
require_relative '../legacy_spec_helper'
require 'wiki_controller'

describe WikiController, type: :controller do
  render_views

  fixtures :all

  before do
    User.current = nil
  end

  def wiki
    Project.first.wiki
  end

  def redirect_page
    wiki.find_page(wiki.start_page) || wiki.pages.first
  end

  it 'shows start page' do
    get :show, params: { project_id: 'ecookbook' }
    assert_response :success
    assert_template 'show'
    assert_select 'h1', content: /CookBook documentation/

    # child_pages macro
    assert_select 'ul',
                  attributes: { class: 'pages-hierarchy' },
                  child: {
                    tag: 'li',
                    child: {
                      tag: 'a',
                      attributes: { href: '/projects/ecookbook/wiki/Page_with_an_inline_image' },
                      content: 'Page with an inline image'
                    }
                  }
  end

  it 'shows page with name' do
    get :show, params: { project_id: 1, id: 'Another page' }
    assert_response :success
    assert_template 'show'
    assert_select 'h1', content: /Another page/
  end

  it 'shows unexistent page without edit right' do
    get :show, params: { project_id: 1, id: 'Unexistent page' }
    assert_response 404
  end

  it 'shows unexistent page with edit right' do
    session[:user_id] = 2
    get :show, params: { project_id: 1, id: 'Unexistent page' }
    assert_response :success
    assert_template 'new'
  end

  it 'histories with one version' do
    create :wiki_content_journal,
           journable_id: 2,
           data: build(:journal_wiki_content_journal,
                       text: "h1. Another page\n\n\nthis is a link to ticket: #2")
    get :history, params: { project_id: 1, id: 'Another page' }
    assert_response :success
    assert_template 'history'
    refute_nil assigns(:versions)
    assert_equal 1, assigns(:versions).size
    assert_select 'input[type=submit][name=commit]', false
  end

  it 'diffs' do
    journal_from = create :wiki_content_journal,
                          journable_id: 1,
                          data: build(:journal_wiki_content_journal,
                                      text: 'h1. CookBook documentation')
    journal_to = create :wiki_content_journal,
                        journable_id: 1,
                        data: build(:journal_wiki_content_journal,
                                    text: "h1. CookBook documentation\n\n\nSome updated [[documentation]] here...")

    get :diff,
        params: { project_id: 1, id: 'CookBook documentation', version: journal_to.version, version_from: journal_from.version }
    assert_response :success
    assert_template 'diff'
    assert_select 'ins', attributes: { class: 'diffins' },
                         content: /updated/
  end

  it 'annotates' do
    create :wiki_content_journal,
           journable_id: 1,
           data: build(:journal_wiki_content_journal,
                       text: 'h1. CookBook documentation')
    journal_to = create :wiki_content_journal,
                        journable_id: 1,
                        data: build(:journal_wiki_content_journal,
                                    text: "h1. CookBook documentation\n\n\nSome [[documentation]] here...")

    get :annotate, params: { project_id: 1, id: 'CookBook documentation', version: journal_to.version }
    assert_response :success
    assert_template 'annotate'
    # Line 1
    assert_select 'tr',
                  child: { tag: 'th', attributes: { class: 'line-num' }, content: '1' },
                  child: { tag: 'td', attributes: { class: 'author' }, content: /John Smith/ },
                  child: { tag: 'td', content: /h1\. CookBook documentation/ }
    # Line 2
    assert_select 'tr',
                  child: { tag: 'th', attributes: { class: 'line-num' }, content: '2' },
                  child: { tag: 'td', attributes: { class: 'author' }, content: /redMine Admin/ },
                  child: { tag: 'td', content: /Some updated \[\[documentation\]\] here/ }
  end

  it 'gets rename' do
    session[:user_id] = 2
    get :rename, params: { project_id: 1, id: 'Another page' }
    assert_response :success
    assert_template 'rename'
  end

  it 'gets rename child page' do
    session[:user_id] = 2
    get :rename, params: { project_id: 1, id: 'Child 1' }
    assert_response :success
    assert_template 'rename'
  end

  it 'renames with redirect' do
    session[:user_id] = 2
    patch :rename, params: { project_id: 1, id: 'Another page',
                             page: { title: 'Another renamed page',
                                     redirect_existing_links: 1 } }
    assert_redirected_to action: 'show', project_id: 'ecookbook', id: 'another-renamed-page'
    # Check redirects
    refute_nil wiki.find_page('Another page')
    assert_nil wiki.find_page('Another page', with_redirect: false)
  end

  it 'renames without redirect' do
    session[:user_id] = 2
    patch :rename, params: { project_id: 1, id: 'another-page',
                             page: { title: 'Another renamed page',
                                     redirect_existing_links: '0' } }
    assert_redirected_to action: 'show', project_id: 'ecookbook', id: 'another-renamed-page'
    # Check that there's no redirects
    assert_nil wiki.find_page('Another page')
  end

  it 'destroys child' do
    session[:user_id] = 2
    delete :destroy, params: { project_id: 1, id: 'Child 1' }
    assert_redirected_to action: 'index', project_id: 'ecookbook', id: redirect_page
  end

  it 'destroys parent' do
    session[:user_id] = 2
    assert_no_difference('WikiPage.count') do
      delete :destroy, params: { project_id: 1, id: 'Another page' }
    end
    assert_response :success
    assert_template 'destroy'
  end

  it 'destroys parent with nullify' do
    session[:user_id] = 2
    assert_difference('WikiPage.count', -1) do
      delete :destroy, params: { project_id: 1, id: 'Another page', todo: 'nullify' }
    end
    assert_redirected_to action: 'index', project_id: 'ecookbook', id: redirect_page
    assert_nil WikiPage.find_by(id: 2)
  end

  it 'destroys parent with cascade' do
    session[:user_id] = 2
    assert_difference('WikiPage.count', -3) do
      delete :destroy, params: { project_id: 1, id: 'Another page', todo: 'destroy' }
    end
    assert_redirected_to action: 'index', project_id: 'ecookbook', id: redirect_page
    assert_nil WikiPage.find_by(id: 2)
    assert_nil WikiPage.find_by(id: 5)
  end

  it 'destroys parent with reassign' do
    session[:user_id] = 2
    assert_difference('WikiPage.count', -1) do
      delete :destroy, params: { project_id: 1, id: 'Another page', todo: 'reassign', reassign_to_id: 1 }
    end
    assert_redirected_to action: 'index', project_id: 'ecookbook', id: redirect_page
    assert_nil WikiPage.find_by(id: 2)
    assert_equal WikiPage.find(1), WikiPage.find_by(id: 5).parent
  end

  it 'indexes' do
    get :index, params: { project_id: 'ecookbook' }
    assert_response :success
    assert_template 'index'
    pages = assigns(:pages)
    refute_nil pages
    assert_equal wiki.pages.size, pages.size

    assert_select 'ul', attributes: { class: 'pages-hierarchy' },
                        child: { tag: 'li', child: { tag: 'a', attributes: { href: '/projects/ecookbook/wiki/CookBook%20documentation' },
                                                     content: 'CookBook documentation' },
                                 child: { tag: 'ul',
                                          child: { tag: 'li',
                                                   child: { tag: 'a', attributes: { href: '/projects/ecookbook/wiki/Page%20with%20an%20inline%20image' },
                                                            content: 'Page with an inline image' } } } },
                        child: { tag: 'li', child: { tag: 'a', attributes: { href: '/projects/ecookbook/wiki/Another%20page' },
                                                     content: 'Another page' } }
  end

  it 'indexes should include atom link' do
    get :index, params: { project_id: 'ecookbook' }
    assert_select 'a', attributes: { href: '/projects/ecookbook/activity.atom?show_wiki_edits=1' }
  end

  context 'GET :export' do
    context 'with an authorized user to export the wiki' do
      before do
        session[:user_id] = 2
        get :export, params: { project_id: 'ecookbook' }
      end

      it { is_expected.to respond_with :success }
      it { should_assign_to :pages }
      it { should_respond_with_content_type 'text/html' }

      it 'exports all of the wiki pages to a single html file' do
        assert_select 'a[name=?]', 'cookbook-documentation'
        assert_select 'a[name=?]', 'another-page'
        assert_select 'a[name=?]', 'page-with-an-inline-image'
      end
    end

    context 'with an unauthorized user' do
      before do
        get :export, params: { project_id: 'ecookbook' }

        it { is_expected.to respond_with :redirect }
        it { is_expected.to redirect_to('wiki index') { { action: 'show', project_id: @project, id: nil } } }
      end
    end
  end

  it 'does not found' do
    get :show, params: { project_id: 999 }
    assert_response 404
  end

  it 'protects page' do
    page = WikiPage.find_by(wiki_id: 1, title: 'Another page')
    assert !page.protected?
    session[:user_id] = 2
    post :protect, params: { project_id: 1, id: page.title, protected: '1' }
    assert_redirected_to action: 'show', project_id: 'ecookbook', id: 'another-page'
    assert page.reload.protected?
  end

  it 'unprotects page' do
    page = WikiPage.find_by(wiki_id: 1, title: 'CookBook documentation')
    assert page.protected?
    session[:user_id] = 2
    post :protect, params: { project_id: 1, id: page.title, protected: '0' }
    assert_redirected_to action: 'show', project_id: 'ecookbook', id: 'cookbook-documentation'
    assert !page.reload.protected?
  end

  it 'shows page with edit link' do
    session[:user_id] = 2
    get :show, params: { project_id: 1 }
    assert_response :success
    assert_template 'show'
    assert_select 'a', attributes: { href: '/projects/1/wiki/CookBook+documentation/edit' }
  end

  it 'shows page without edit link' do
    session[:user_id] = 4
    get :show, params: { project_id: 1 }
    assert_response :success
    assert_template 'show'
    assert_select('a', { attributes: { href: '/projects/1/wiki/CookBook+documentation/edit' } }, false)
  end

  it 'edits unprotected page' do
    # Non members can edit unprotected wiki pages
    session[:user_id] = 4
    get :edit, params: { project_id: 1, id: 'Another page' }
    assert_response :success
    assert_template 'edit'
  end

  it 'edits protected page by nonmember' do
    # Non members can't edit protected wiki pages
    session[:user_id] = 4
    get :edit, params: { project_id: 1, id: 'CookBook documentation' }
    assert_response 403
  end

  it 'edits protected page by member' do
    session[:user_id] = 2
    get :edit, params: { project_id: 1, id: 'CookBook documentation' }
    assert_response :success
    assert_template 'edit'
  end

  it 'histories of non existing page should return 404' do
    get :history, params: { project_id: 1, id: 'Unknown page' }
    assert_response 404
  end
end
