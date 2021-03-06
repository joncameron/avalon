# Copyright 2011-2015, The Trustees of Indiana University and Northwestern
#   University.  Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
# 
# You may obtain a copy of the License at
# 
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software distributed 
#   under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
#   CONDITIONS OF ANY KIND, either express or implied. See the License for the 
#   specific language governing permissions and limitations under the License.
# ---  END LICENSE_HEADER BLOCK  ---

require 'spec_helper'

describe MediaObjectsController, type: :controller do
  render_views

  describe "#new" do
    let!(:collection) { FactoryGirl.create(:collection) }
    before(:each) do
      request.env["HTTP_REFERER"] = '/'
    end

    it "should redirect to sign in page with a notice when unauthenticated" do
      expect { get 'new', collection_id: collection.pid }.not_to change { MediaObject.count }
      flash[:notice].should_not be_nil
      response.should redirect_to(new_user_session_path)
    end
  
    it "should redirect to home page with a notice when authenticated but unauthorized" do
      login_as :user
      expect { get 'new', collection_id: collection.pid }.not_to change { MediaObject.count }
      flash[:notice].should_not be_nil
      response.should redirect_to(root_path)
    end

    it "should not let manager of other collections create an item in this collection" do
      skip
    end

    context "Default permissions should be applied" do
      it "should be editable by the creator" do
        login_user collection.managers.first
        expect { get 'new', collection_id: collection.pid }.to change { MediaObject.count }
        pid = MediaObject.all.last.pid
        response.should redirect_to(edit_media_object_path(id: pid))
      end

      it "should copy default permissions from its owning collection" do
        login_user collection.depositors.first

        get 'new', collection_id: collection.pid 
         
        #MediaObject.all.last.edit_users.should include(collection.managers)
        #MediaObject.all.last.edit_users.should include(collection.depositors)
      end
    end

  end

  describe "#edit" do
    let!(:media_object) { FactoryGirl.create(:media_object) }

    it "should redirect to sign in page with a notice when unauthenticated" do   
      get 'edit', id: media_object.pid
      flash[:notice].should_not be_nil
      response.should redirect_to(new_user_session_path)
    end
  
    it "should redirect to show page with a notice when authenticated but unauthorized" do
      login_as :user
      
      get 'edit', id: media_object.pid
      flash[:notice].should_not be_nil
      response.should redirect_to(media_object_path(media_object.pid) )
    end

    it "should redirect to first workflow step if authorized to edit" do
       login_user media_object.collection.managers.first

       get 'edit', id: media_object.pid
       response.should be_success
       response.should render_template "_#{HYDRANT_STEPS.first.template}"
     end
    
    it "should not default to the Access Control page" do
      skip "[VOV-1165] Wait for product owner feedback on which step to default to"
    end

    context "Updating the metadata should result in valid input" do
      it "should ignore the PID if provided as a parameter"
      it "should ignore invalid attributes"
      it "should be able to retrieve an existing record from Fedora" do
        media_object.workflow.last_completed_step = 'resource-description'
        media_object.save
         
        # Set the task so that it can get to the resource-description step
        login_user media_object.collection.managers.first
        get :edit, {id: media_object.pid, step: 'resource-description'}
        response.response_code.should == 200
      end
    end

    context "Persisting Permalinks" do
      before(:each) { login_user mo.collection.managers.first }
      context "Persisting Permalinks on unpublished mediaobject" do
        subject(:mo) { media_object }
        it "should persist new permalink on unpublished media_object" do 
          expect { put 'update', id: mo.pid, step: 'resource-description', 
                   media_object: { permalink: 'newpermalink', title: 'newtitle', 
                                   creator: 'newcreator', date_issued: 'newdateissued' }}
            .to change { MediaObject.find(mo.pid).permalink } 
            .to('newpermalink')
        end
        it "should persist new permalink on unpublished media_object part" do 
          part1 = FactoryGirl.create(:master_file, mediaobject: mo)
          expect {put 'update', id: mo.pid, step: 'file-upload', 
                  parts: { part1.pid => { permalink: 'newpermalinkpart' }}}
            .to change { MasterFile.find(part1.pid).permalink }
            .to('newpermalinkpart')
        end
      end
      context "Persisting Permalinks on published mediaobject" do
        subject(:mo) { FactoryGirl.create(:published_media_object, permalink: 'oldpermalink') }
        it "should persist updated permalink on published media_object" do
          expect { put 'update', id: mo.pid, step: 'resource-description', 
                   media_object: { permalink: 'newpermalink', title: mo.title, 
                                   creator: mo.creator, date_issued: mo.date_issued }}
            .to change { MediaObject.find(mo.pid).permalink }
            .to('newpermalink')
        end
        it "should persist updated permalink on published media_object part" do
          part1 = FactoryGirl.create(:master_file, permalink: 'oldpermalinkpart1', mediaobject: mo)
          expect { put 'update', id: mo.pid, step: 'file-upload', 
                   parts: { part1.pid => { permalink: 'newpermalinkpart' }}}
            .to change { MasterFile.find(part1.pid).permalink }
            .to('newpermalinkpart')
        end
      end
    end
  end

  describe "#show" do
    let!(:media_object) { FactoryGirl.create(:published_media_object, visibility: 'public') }

    context "Known items should be retrievable" do
      it "should be accesible by its PID" do
        get :show, id: media_object.pid
        response.response_code.should == 200
      end

      it "should return an error if the PID does not exist" do
        expect(MediaObject).to receive(:find).with('no-such-object') { raise ActiveFedora::ObjectNotFoundError }
        get :show, id: 'no-such-object'
        response.response_code.should == 404
      end

      it "should be available to a manager when unpublished" do
        login_user media_object.collection.managers.first
        get 'show', id: media_object.pid
        response.should_not redirect_to new_user_session_path
      end

      it "should provide a JSON stream description to the client" do
        master_file = FactoryGirl.create(:master_file)
        master_file.mediaobject = media_object
        master_file.save

        mopid = media_object.pid
        media_object = MediaObject.find(mopid)

        media_object.parts.collect { |part| 
          get 'show', id: media_object.pid, format: 'json', content: part.pid
          json_obj = JSON.parse(response.body)
          json_obj['is_video'].should == part.is_video?
        }
      end
    end

    context "Conditional Share partials should be rendered" do
      context "Normal login" do
        it "administrators: should include lti, embed, and share" do
          login_as(:administrator)
          get :show, id: media_object.pid
          expect(response).to render_template(:_share_resource)
          expect(response).to render_template(:_embed_resource)
          expect(response).to render_template(:_lti_url)
        end
        it "managers: should include lti, embed, and share" do
          login_user media_object.collection.managers.first
          get :show, id: media_object.pid
          expect(response).to render_template(:_share_resource)
          expect(response).to render_template(:_embed_resource)
          expect(response).to render_template(:_lti_url)
        end
        it "editors: should include lti, embed, and share" do
          login_user media_object.collection.editors.first
          get :show, id: media_object.pid
          expect(response).to render_template(:_share_resource)
          expect(response).to render_template(:_embed_resource)
          expect(response).to render_template(:_lti_url)
        end
        it "others: should include embed and share and NOT lti" do
          login_as(:user)
          get :show, id: media_object.pid
          expect(response).to render_template(:_share_resource)
          expect(response).to render_template(:_embed_resource)
          expect(response).to_not render_template(:_lti_url)
        end
      end
      context "LTI login" do
        it "administrators/managers/editors: should include lti, embed, and share" do
          user = login_lti 'administrator'
          lti_group = @controller.user_session[:virtual_groups].first
          mo = FactoryGirl.create(:published_media_object, visibility: 'private', read_groups: [lti_group])
          get :show, id: media_object.pid
          expect(response).to render_template(:_share_resource)
          expect(response).to render_template(:_embed_resource)
          expect(response).to render_template(:_lti_url)
        end
        it "others: should include only lti" do
          user = login_lti 'student'
          lti_group = @controller.user_session[:virtual_groups].first
          mo = FactoryGirl.create(:published_media_object, visibility: 'private', read_groups: [lti_group])
          get :show, id: media_object.pid
          expect(response).to_not render_template(:_share_resource)
          expect(response).to_not render_template(:_embed_resource)
          expect(response).to render_template(:_lti_url)
        end
      end
      context "No share tabs rendered" do
        it "should not render Share button" do
          @controller.stub(:evaluate_if_unless_configuration).and_return false
          expect(response).to_not render_template(:_share)
        end
      end
      context "No LTI configuration" do
        around do |example|
          providers = Avalon::Authentication::Providers
          Avalon::Authentication::Providers = Avalon::Authentication::Providers.reject{|p| p[:provider] == :lti}
          example.run
          Avalon::Authentication::Providers = providers
        end
        it "should not include lti" do
          login_as(:administrator)
          get :show, id: media_object.pid
          expect(response).to render_template(:_share_resource)
          expect(response).to render_template(:_embed_resource)
          expect(response).to_not render_template(:_lti_url)
        end
      end
    end

    context "correctly handle unfound streams/sections" do
      subject(:mo){FactoryGirl.create(:media_object_with_master_file)}
      before do 
        mo.save(validate: false)
        login_user mo.collection.managers.first        
      end
      it "redirects to first stream when currentStream is nil" do
        expect(get 'show', id: mo.pid, content: 'foo').to redirect_to(media_object_path(id: mo.pid))        
      end
      it "responds with 404 when non-existant section is requested" do
        get 'show', id: mo.pid, part: 100
        expect(response.code).to eq('404')  
      end
    end

    describe 'Redirect back to media object after sign in' do
      let(:media_object){ FactoryGirl.create(:media_object, visibility: 'private') }

      context 'Before sign in' do
        it 'persists the current url on the session' do
          get 'show', id: media_object.pid
          session[:previous_url].should eql media_object_path(media_object)
        end
      end

      context 'After sign in' do
        before do 
          @user = FactoryGirl.create(:user)
          @media_object = FactoryGirl.create(:media_object, visibility: 'private', read_users: [@user.username] )
        end
        it 'redirects to the previous url' do
        end
        it 'removes the previous url from the session' do
        end
      end
    end
    
    context "Items should not be available to unauthorized users" do
      it "should redirect to sign in when not logged in and item is unpublished" do
        media_object.publish!(nil)
        media_object.should_not be_published
        get 'show', id: media_object.pid
        response.should redirect_to new_user_session_path
      end

      it "should redirect to home page when logged in and item is unpublished" do
        media_object.publish!(nil)
        media_object.should_not be_published
        login_as :user
        get 'show', id: media_object.pid
        response.should redirect_to root_path
      end
    end
  end
    
  describe "#destroy" do
    let!(:collection) { FactoryGirl.create(:collection) }
    before(:each) do 
      login_user collection.managers.first
    end
    
    it "should remove the MediaObject and MasterFiles from the system" do
      media_object = FactoryGirl.create(:media_object_with_master_file, collection: collection)
      delete :destroy, id: media_object.pid
      expect(flash[:notice]).to include("success")
      expect(MediaObject.exists?(media_object.pid)).to be_falsey
      expect(MasterFile.exists?(media_object.parts.first.id)).to be_falsey
    end

    it "should fail when id doesn't exist" do
      delete :destroy, id: 'avalon:this-pid-is-fake'
      expect(response.code).to eq '404'
    end

    it "should fail if user is not authorized" do
      media_object = FactoryGirl.create(:media_object)
      expect(delete :destroy, id: media_object.id).to redirect_to root_path
      expect(flash[:notice]).to include("permission denied")
    end

    it "should remove multiple items" do
      media_objects = []
      3.times { media_objects << FactoryGirl.create(:media_object, collection: collection) }
      delete :destroy, id: media_objects.map(&:id)
      expect(flash[:notice]).to include('3 media objects')
      media_objects.each {|mo| expect(MediaObject.exists?(mo.pid)).to be_falsey }
    end
  end

  describe "#update_status" do
    let!(:collection) { FactoryGirl.create(:collection) }
    before(:each) do
      login_user collection.managers.first
      request.env["HTTP_REFERER"] = '/'
    end

    context 'publishing' do
      before(:each) do
        Permalink.on_generate { |obj| "http://example.edu/permalink" }
      end
      it 'publishes media object' do
	media_object = FactoryGirl.create(:media_object, collection: collection)
        get 'update_status', id: media_object.pid, status: 'publish'
        media_object.reload
        expect(media_object).to be_published
        expect(media_object.permalink).to be_present
      end

      it "should fail when id doesn't exist" do
	get 'update_status', id: 'avalon:this-pid-is-fake', status: 'publish'
	expect(response.code).to eq '404'
      end

      it "should fail if user is not authorized" do
	media_object = FactoryGirl.create(:media_object)
	expect(get 'update_status', id: media_object.pid, status: 'publish').to be_redirect
	expect(flash[:notice]).to include("permission denied")
      end

      it "should publish multiple items" do
	media_objects = []
	3.times { media_objects << FactoryGirl.create(:media_object, collection: collection) }
        get 'update_status', id: media_objects.map(&:id), status: 'publish'
	expect(flash[:notice]).to include('3 media objects')
        media_objects.each do |mo|
          mo.reload
	  expect(mo).to be_published
	  expect(mo.permalink).to be_present
        end
      end
    end

    context 'unpublishing' do
      it 'unpublishes media object' do
        media_object = FactoryGirl.create(:published_media_object, collection: collection)
        get 'update_status', :id => media_object.pid, :status => 'unpublish'
        media_object.reload
        expect(media_object).not_to be_published
      end

      it "should fail when id doesn't exist" do
	get 'update_status', id: 'avalon:this-pid-is-fake', status: 'unpublish'
	expect(response.code).to eq '404'
      end

      it "should fail if user is not authorized" do
	media_object = FactoryGirl.create(:media_object)
	expect(get 'update_status', id: media_object.pid, status: 'unpublish').to be_redirect
	expect(flash[:notice]).to include("permission denied")
      end

      it "should unpublish multiple items" do
	media_objects = []
	3.times { media_objects << FactoryGirl.create(:published_media_object, collection: collection) }
        get 'update_status', id: media_objects.map(&:id), status: 'unpublish'
	expect(flash[:notice]).to include('3 media objects')
        media_objects.each do |mo|
          mo.reload
	  expect(mo).not_to be_published
        end
      end
    end
  end

  describe "#update" do
    it 'updates the order' do

      media_object = FactoryGirl.create(:media_object)
      media_object.parts << FactoryGirl.create(:master_file)
      media_object.parts << FactoryGirl.create(:master_file)
      master_file_pids = media_object.parts.map(&:id)
      media_object.section_pid = master_file_pids
      media_object.save( validate: false )

      login_user media_object.collection.managers.first
      
      put 'update', :id => media_object.pid, :masterfile_ids => master_file_pids.reverse, :step => 'structure'
      media_object.reload
      media_object.section_pid.should eq master_file_pids.reverse
    end
    it 'sets the MIME type' do
      media_object = FactoryGirl.create(:media_object)
      media_object.parts << FactoryGirl.create(:master_file_with_derivative)
      media_object.section_pid = media_object.parts.map(&:id)
      media_object.set_media_types!
      media_object.save( validate: false )
      media_object.reload
      expect(media_object.descMetadata.media_type).to eq(["video/mp4"])
    end
  end
end
