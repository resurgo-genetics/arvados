class AddOutputAndLogUuidsToContainerRequestSearchIndex < ActiveRecord::Migration
  def up
    begin
      remove_index :container_requests, :name => 'container_requests_search_index'
    rescue
    end
    add_index :container_requests,
              ["uuid", "owner_uuid", "modified_by_client_uuid", "modified_by_user_uuid", "name", "state", "requesting_container_uuid", "container_uuid", "container_image", "cwd", "output_path", "output_uuid", "log_uuid"],
              name: "container_requests_search_index"
  end

  def down
    begin
      remove_index :container_requests, :name => 'container_requests_search_index'
    rescue
    end
	  add_index :container_requests,
              ["uuid", "owner_uuid", "modified_by_client_uuid", "modified_by_user_uuid", "name", "state", "requesting_container_uuid", "container_uuid", "container_image", "cwd", "output_path"],
              name: "container_requests_search_index"
  end
end
